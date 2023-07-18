import SwiftSyntax
import SwiftSyntaxBuilder

extension FunctionSignatureSyntax {
    func asFunctionType() -> FunctionTypeSyntax {
        return FunctionTypeSyntax(
            arguments: TupleTypeElementListSyntax {
                for argument in self.input.parameterList {
                    TupleTypeElementSyntax(
                        type: argument.type,
                        ellipsis: argument.ellipsis
                    )
                }
            },
            effectSpecifiers: self.effectSpecifiers.map { specifiers in
                TypeEffectSpecifiersSyntax(
                    asyncSpecifier: specifiers.asyncSpecifier,
                    throwsSpecifier: specifiers.throwsSpecifier
                )
            },
            output: self.output ?? ReturnClauseSyntax(returnType: SimpleTypeIdentifierSyntax(name: .identifier("Void")))
        )
    }
}