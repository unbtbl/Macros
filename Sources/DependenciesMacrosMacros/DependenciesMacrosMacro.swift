import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct AutoDependency {
    var declaration: DeclGroupSyntax
    var identifier: TokenSyntax
    var protocolName: String {
        "\(identifier.text)Protocol"
    }

    init(
        node: AttributeSyntax,
        declaration: some SyntaxProtocol
    ) throws {
        guard
            let group = declaration.asProtocol(DeclGroupSyntax.self),
            let identifier = declaration.asProtocol(IdentifiedDeclSyntax.self)?.identifier,
            !declaration.is(ExtensionDeclSyntax.self),
            !declaration.is(ProtocolDeclSyntax.self)
        else {
            throw DiagnosticsError(
                diagnostics: [
                    DependenciesMacroDiagnostic.unsupportedType(declaration).at(Syntax(node))
                ]
            )
        }

        self.declaration = group
        self.identifier = identifier
    }

    func generateProtocol() -> DeclSyntax {
        let body = MemberDeclListSyntax {
            for member in declaration.memberBlock.members {
                if let convertible = member.decl.asProtocol(ProtocolRequirementConvertibleSyntax.self) {
                    try! convertible.asProtocolRequirement()
                }
            }
        }.trimmed

        return """
        protocol \(raw: protocolName): AnyObject {
            \(body)
        }
        """
    }
}

extension AutoDependency: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let instance = try Self(node: node, declaration: declaration)

        return [
            instance.generateProtocol()
        ]
    }
}

extension AutoDependency: ConformanceMacro {
    public static func expansion(of node: AttributeSyntax, providingConformancesOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [(TypeSyntax, GenericWhereClauseSyntax?)] {
        let instance = try Self(node: node, declaration: declaration)

        return [ ( "\(raw: instance.protocolName)", nil) ]
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
