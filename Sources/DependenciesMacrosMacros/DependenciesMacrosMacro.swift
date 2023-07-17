import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct AutoDependency {}

extension AutoDependency: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
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

        let body = try MemberDeclListSyntax {
            for member in group.memberBlock.members {
                if let convertible = member.decl.asProtocol(ProtocolRequirementConvertibleSyntax.self) {
                    try convertible.asProtocolRequirement()
                }
            }
        }.trimmed

        return [
            """
            protocol \(raw: identifier.text)Protocol {
                \(body)
            }
            """
        ]
    }
}

enum DependenciesMacroDiagnostic {
    case unsupportedType(DeclSyntaxProtocol)
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
