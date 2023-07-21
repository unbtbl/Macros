import SwiftSyntax
import SwiftSyntaxBuilder

enum ProtocolRequirementConvertibleSyntaxError: Error {
    case missingTypeAnnotation
    case missingBinding
}

protocol ProtocolRequirementConvertibleSyntax: SyntaxProtocol {
    func asProtocolRequirement() throws -> DeclSyntaxProtocol
}

extension DeclSyntaxProtocol {
    func asProtocol(_: ProtocolRequirementConvertibleSyntax.Protocol) -> ProtocolRequirementConvertibleSyntax? {
        DeclSyntax(self).asProtocol(DeclSyntaxProtocol.self) as? ProtocolRequirementConvertibleSyntax
    }
}

extension FunctionDeclSyntax: ProtocolRequirementConvertibleSyntax {
    func asProtocolRequirement() -> DeclSyntaxProtocol {
        self.with(\.body, nil).with(\.modifiers, nil)
    }
}

extension VariableDeclSyntax: ProtocolRequirementConvertibleSyntax {
    func asProtocolRequirement() throws -> DeclSyntaxProtocol {
        guard let binding = bindings.first else {
            throw ProtocolRequirementConvertibleSyntaxError.missingBinding
        }

        guard let type = binding.typeAnnotation?.type else {
            throw ProtocolRequirementConvertibleSyntaxError.missingTypeAnnotation
        }

        let body = bindingKeyword.tokenKind == .keyword(.let)
            ? "get"
            : "get set"

        return "var \(binding.pattern): \(type) { \(raw: body) }" as DeclSyntax
    }
}
