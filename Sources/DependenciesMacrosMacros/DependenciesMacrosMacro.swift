import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

enum DependencyKind {
    case `class`
    case `struct`
    case `actor`
}

public struct AutoDependencyMacro {
    var declaration: DeclGroupSyntax
    var identifier: TokenSyntax
    var protocolName: String {
        "\(identifier.text)Protocol"
    }
    var mockName: String {
        "\(identifier.text)Mock"
    }
    var declarationIsPublic: Bool {
        declaration.modifiers?.contains(where: { $0.name.text == "public" }) == true
    }
    var dependencyKind: DependencyKind
    var declarationInheritanceClause: TypeInheritanceClauseSyntax? {
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.inheritanceClause
        } else if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.inheritanceClause
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            return actorDecl.inheritanceClause
        } else {
            return nil
        }
    }
    var declarationIsSendable: Bool {
        declarationInheritanceClause?.inheritedTypeCollection.contains(where: { $0.typeName.as(SimpleTypeIdentifierSyntax.self)?.name.text == "Sendable" }) == true
    }

    init(
        node: AttributeSyntax,
        declaration: some SyntaxProtocol
    ) throws {
        guard
            let group = declaration.asProtocol(DeclGroupSyntax.self),
            let identifier = declaration.asProtocol(IdentifiedDeclSyntax.self)?.identifier
        else {
            throw DiagnosticsError(
                diagnostics: [
                    DependenciesMacroDiagnostic.unsupportedType(declaration).at(Syntax(node))
                ]
            )
        }

        self.declaration = group
        self.identifier = identifier

        if declaration.is(ClassDeclSyntax.self) {
            self.dependencyKind = .class
        } else if declaration.is(StructDeclSyntax.self) {
            self.dependencyKind = .struct
        } else if declaration.is(ActorDeclSyntax.self) {
            self.dependencyKind = .actor
        } else {
            throw DiagnosticsError(
                diagnostics: [
                    DependenciesMacroDiagnostic.unsupportedType(declaration).at(Syntax(node))
                ]
            )
        }
    }

    func generateProtocol() throws -> ProtocolDeclSyntax {
        let protocolDecl = try ProtocolDeclSyntax("protocol \(raw: protocolName)") {
            for member in declaration.memberBlock.members where protocolIncludes(member.decl) {
                if let convertible = member.decl.asProtocol(ProtocolRequirementConvertibleSyntax.self) {
                    try convertible.asProtocolRequirement()
                }
            }
        }

        let inheritanceClause = TypeInheritanceClauseSyntax {
            if dependencyKind == .class {
                InheritedTypeSyntax(typeName: "AnyObject" as TypeSyntax)
            } else if dependencyKind == .actor {
                InheritedTypeSyntax(typeName: "AnyActor" as TypeSyntax)
            }

            // If the declaration is Sendable, add that to the inheritance clause
            if declarationIsSendable {
                InheritedTypeSyntax(typeName: "Sendable" as TypeSyntax)
            }
        }

        return protocolDecl
            .with(\.inheritanceClause, inheritanceClause.inheritedTypeCollection.isEmpty ? nil : inheritanceClause)
            .with(\.modifiers, declarationIsPublic ? [DeclModifierSyntax(name: .keyword(.public))] : nil)
    }

    func generateMock() throws -> DeclSyntaxProtocol {
        let inheritanceClause = TypeInheritanceClauseSyntax {
            InheritedTypeSyntax(typeName: "\(raw: protocolName)" as TypeSyntax)

            if dependencyKind == .class, declarationIsSendable {
                // Add @unchecked Sendable
                InheritedTypeSyntax(typeName: "@unchecked Sendable" as TypeSyntax)
            }
        }

        var members = try mockMembers()
        let initializer = initializer(for: members.map(\.decl))
        members = members.appending(MemberDeclListItemSyntax(decl: initializer))

        let membersBlock = MemberDeclBlockSyntax(members: members)

        let decl: DeclSyntaxProtocol = switch dependencyKind {
        case .class:
            ClassDeclSyntax(
                modifiers: declarationIsPublic ? [DeclModifierSyntax(name: .keyword(.open))] : nil,
                identifier: .identifier(mockName),
                inheritanceClause: inheritanceClause,
                memberBlock: membersBlock
            )
        case .struct:
            StructDeclSyntax(
                modifiers: declarationIsPublic ? [DeclModifierSyntax(name: .keyword(.public))] : nil,
                identifier: .identifier(mockName),
                inheritanceClause: inheritanceClause,
                memberBlock: membersBlock
            )
        case .actor:
            ActorDeclSyntax(
                modifiers: declarationIsPublic ? [DeclModifierSyntax(name: .keyword(.public))] : nil,
                identifier: .identifier(mockName),
                inheritanceClause: inheritanceClause,
                memberBlock: membersBlock
            )
        }

        return decl
    }

    func mockMembers() throws -> MemberDeclListSyntax {
        let members = declaration.memberBlock.members
            .reduce(into: [DeclSyntaxProtocol]()) { (result, member) in
                result.append(contentsOf: mockMembers(for: member.decl))
            }
            .map { MemberDeclListItemSyntax(decl: $0) }

        return MemberDeclListSyntax(members)
    }

    func mockMembers(for member: some DeclSyntaxProtocol) -> [DeclSyntaxProtocol] {
        guard let funcDecl = member.as(FunctionDeclSyntax.self), protocolIncludes(member) else {
            return []
        }

        let closureVariableIdentifier = "_\(funcDecl.identifier.text)"
        
        let variableDecl = VariableDeclSyntax(
            bindingKeyword: .keyword(.var)
        ) {
            PatternBindingSyntax(
                pattern: "\(raw: closureVariableIdentifier)" as PatternSyntax,
                typeAnnotation: TypeAnnotationSyntax(type: funcDecl.signature.asFunctionType()),
                initializer: InitializerClauseSyntax(
                    value: "unimplemented()" as ExprSyntax
                )
            )
        }
        
        let functionDecl = FunctionDeclSyntax(
            attributes: funcDecl.attributes,
            modifiers: declarationIsPublic ? [DeclModifierSyntax(name: .keyword(.public))] : nil,
            identifier: funcDecl.identifier,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause
        ) {
            let parameters = funcDecl.signature.input.parameterList
                .map { $0.secondName?.text ?? $0.firstName.text }
                .joined(separator: ", ")

            let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
            let isThrowing = funcDecl.signature.effectSpecifiers?.throwsSpecifier != nil

            let closureCall = "\(raw: closureVariableIdentifier)(\(raw: parameters))" as ExprSyntax
            let fullExpression: ExprSyntax = switch (isAsync, isThrowing) {
            case (true, true):
                "try await \(closureCall)"
            case (true, false):
                "await \(closureCall)"
            case (false, true):
                "try \(closureCall)"
            case (false, false):
                closureCall
            }

            "return \(fullExpression)"
        }

        return [
            variableDecl,
            functionDecl
        ]
    }

    func initializer<S: Sequence>(for members: S) -> InitializerDeclSyntax where S.Element: DeclSyntaxProtocol {
        let parametersAndCodeBlockItems: [(parameter: FunctionParameterSyntax, codeBlockItem: CodeBlockItemSyntax)] = members
            .compactMap { (member) -> (FunctionParameterSyntax, CodeBlockItemSyntax)? in
                guard
                    let variable = member.as(VariableDeclSyntax.self),
                    let binding = variable.bindings.first,
                    let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                    let type = binding.typeAnnotation?.type
                else {
                    return nil
                }

                // Remove the _ prefix from the identifier if it exists
                let trimmedIdentifier = identifier.text.hasPrefix("_")
                    ? .identifier(String(identifier.text.dropFirst()))
                    : identifier

                // Add @escaping to the type if it's a function type
                let annotatedType: TypeSyntax = if let functionType = type.as(FunctionTypeSyntax.self) {
                    "@escaping \(functionType)"
                } else {
                    type
                }

                let parameter = FunctionParameterSyntax(
                    firstName: trimmedIdentifier,
                    type: annotatedType,
                    defaultArgument: binding.initializer
                )

                let codeBlockItem: CodeBlockItemSyntax = "self.\(identifier) = \(trimmedIdentifier)"

                return (parameter, codeBlockItem)
            }

        return InitializerDeclSyntax(
            modifiers: declarationIsPublic ? [DeclModifierSyntax(name: .keyword(.public))] : nil,
            signature: FunctionSignatureSyntax(
                input: ParameterClauseSyntax { // We're using the builder here because it automatically inserts commas for us
                    for (parameter, _) in parametersAndCodeBlockItems {
                        parameter
                    }
                }
            ),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(parametersAndCodeBlockItems.map(\.codeBlockItem)))
        )
    }

    func protocolIncludes(_ member: some DeclSyntaxProtocol) -> Bool {
        // If the declaration is public, only public members should be included
        if let member = member.as(FunctionDeclSyntax.self), declarationIsPublic {
            return member.modifiers?.contains(where: { $0.name.text == "public" }) == true
        } else if let member = member.as(VariableDeclSyntax.self), declarationIsPublic {
            return member.modifiers?.contains(where: { $0.name.text == "public" }) == true
        } else {
            return true
        }
    }
}

extension AutoDependencyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let instance = try Self(node: node, declaration: declaration)

        return try [
            instance.generateProtocol().as(DeclSyntax.self),
            instance.generateMock().as(DeclSyntax.self)
        ]
    }
}

extension AutoDependencyMacro: ConformanceMacro {
    public static func expansion(of node: AttributeSyntax, providingConformancesOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [(TypeSyntax, GenericWhereClauseSyntax?)] {
        let instance = try Self(node: node, declaration: declaration)

        return [("\(raw: instance.protocolName)", nil)]
    }
}

extension DeclSyntaxProtocol {
    func `as`(_: DeclSyntax.Type) -> DeclSyntax {
        DeclSyntax(self)
    }
}

enum DependenciesMacroDiagnostic {
    case unsupportedType(SyntaxProtocol)
}

extension DependenciesMacroDiagnostic: DiagnosticMessage {
    var message: String {
        switch self {
        case .unsupportedType(let decl):
            return "AutoDependency cannot be applied to \(decl.kind)"
        }
    }

    var diagnosticID: MessageID {
        let id = switch self {
        case .unsupportedType: "unsupportedType"
        }
        return MessageID(
            domain: "\(Self.self)",
            id: id
        )
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .unsupportedType: .error
        }
    }

    func at(_ node: Syntax) -> Diagnostic {
        Diagnostic(node: node, message: self)
    }
}

@main
public struct DependenciesMacrosPlugin: CompilerPlugin {
    public static let macros: [String: Macro.Type] = [
        "AutoDependency": AutoDependencyMacro.self
    ]

    public let providingMacros = Array(Self.macros.values)

    public init() {}
}

struct DumpSyntaxMacro: PeerMacro {
    static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        dump(declaration)
        return []

    }
}
