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

public struct AutoDependency {
    var declaration: DeclGroupSyntax
    var identifier: TokenSyntax
    var protocolName: String {
        "\(identifier.text)Protocol"
    }
    var mockName: String {
        "\(identifier.text)Mock"
    }
    var dependencyKind: DependencyKind

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
            for member in declaration.memberBlock.members {
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
        }

        return protocolDecl
            .with(\.inheritanceClause, inheritanceClause.inheritedTypeCollection.isEmpty ? nil : inheritanceClause)
    }

    func generateMock() throws -> DeclSyntaxProtocol {
        let inheritanceClause = TypeInheritanceClauseSyntax {
            InheritedTypeSyntax(typeName: "\(raw: protocolName)" as TypeSyntax)
        }

        let membersBlock = MemberDeclBlockSyntax(members: try mockMembers())

        let decl: DeclSyntaxProtocol = switch dependencyKind {
        case .class:
            ClassDeclSyntax(
                identifier: .identifier(mockName),
                inheritanceClause: inheritanceClause,
                memberBlock: membersBlock
            )
        case .struct:
            StructDeclSyntax(
                identifier: .identifier(mockName),
                inheritanceClause: inheritanceClause,
                memberBlock: membersBlock
            )
        case .actor:
            ActorDeclSyntax(
                identifier: .identifier(mockName),
                inheritanceClause: inheritanceClause,
                memberBlock: membersBlock
            )
        }

        return decl
    }

    @MemberDeclListBuilder
    func mockMembers() throws -> MemberDeclListSyntax {
        // For each func in the declaration, generate a mock implementation relying on a closure
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                VariableDeclSyntax(
                    bindingKeyword: .keyword(.var)
                ) {
                    PatternBindingSyntax(
                        pattern: "_\(raw: funcDecl.identifier.text)" as PatternSyntax,
                        typeAnnotation: TypeAnnotationSyntax(type: funcDecl.signature.asFunctionType())
                    )
                }
            }
        }
    }
}

extension AutoDependency: PeerMacro {
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

extension AutoDependency: ConformanceMacro {
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
        "AutoDependency": AutoDependency.self
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
