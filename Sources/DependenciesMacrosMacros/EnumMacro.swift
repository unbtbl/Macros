import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftBasicFormat

struct NotEnumDiagnosticMessage: DiagnosticMessage {
    let message: String = "Macro can only be applied to Enums"
    let diagnosticID: MessageID = .init(domain: "unbtbl-macros", id: "enum-codable")
    let severity: DiagnosticSeverity = .error
}

struct UnsuportedTypeDiagnosticMessage: DiagnosticMessage, Error {
    let message: String = "Associated value type is not supported"
    let diagnosticID: MessageID = .init(domain: "unbtbl-macros", id: "enum-case-value-type")
    let severity: DiagnosticSeverity = .error
}

struct MissingEnumCaseLabelDiagnosticMessage: DiagnosticMessage, Error {
    let message: String = "Associated value type in Enum Case is missing a label"
    let diagnosticID: MessageID = .init(domain: "unbtbl-macros", id: "enum-case-value-missing-label")
    let severity: DiagnosticSeverity = .error
}

internal struct EnumCase {
    struct AssociatedValue {
        let firstName: TokenSyntax
        let type: TokenSyntax
    }

    let identifier: TokenSyntax
    let associatedValues: [AssociatedValue]?

    var tupleExpression: TupleExprSyntax? {
        guard let associatedValues = associatedValues else {
            return nil
        }

        return TupleExprSyntax {
            TupleExprElementListSyntax {
                for associatedValue in associatedValues {
                    TupleExprElementSyntax(
                        expression: UnresolvedPatternExprSyntax(
                            pattern: ValueBindingPatternSyntax(
                                bindingKeyword: .keyword(.let), 
                                valuePattern: IdentifierPatternSyntax(identifier: associatedValue.firstName)
                            )
                        )
                    )
                }
            }
        }
    }

    var tupleParameters: TupleTypeElementListSyntax? {
        guard let associatedValues = associatedValues else {
            return nil
        }

        return TupleTypeElementListSyntax {
            for associatedValue in associatedValues {
                TupleTypeElementSyntax(
                    name: associatedValue.firstName,
                    type: SimpleTypeIdentifierSyntax(name: associatedValue.type)
                )
            }
        }
    }

    init?(_ enumCase: EnumCaseDeclSyntax, in context: some MacroExpansionContext) {
        guard
            let caseElement = enumCase.elements.first?.as(EnumCaseElementSyntax.self)
        else {
            return nil
        }

        self.identifier = caseElement.identifier
        self.associatedValues = try? caseElement.associatedValue?.parameterList.map { parameter in
            guard let typeName = parameter.type.as(SimpleTypeIdentifierSyntax.self)?.name else {
                let error = UnsuportedTypeDiagnosticMessage()
                context.diagnose(Diagnostic(
                    node: parameter._syntaxNode,
                    message: error
                ))
                throw UnsuportedTypeDiagnosticMessage()
            }

            guard let firstName = parameter.firstName else {
                let error = MissingEnumCaseLabelDiagnosticMessage()
                context.diagnose(Diagnostic(
                    node: parameter._syntaxNode,
                    message: error
                ))
                throw error
            }

            return AssociatedValue(
                firstName: firstName,
                type: typeName
            )
        }
    }
}

public struct EnumCodableMacro: MemberMacro {
    var declaration: DeclGroupSyntax
    private var cases: [EnumCase]

    func generateSubTypeEnum(context: some MacroExpansionContext) -> EnumDeclSyntax {
        try! EnumDeclSyntax("enum SubType: String, Codable") {
            MemberDeclListItemSyntax(decl: EnumCaseDeclSyntax {
                for enumCase in self.cases {
                    EnumCaseElementSyntax(identifier: enumCase.identifier)
                }
            })
        }
    }

    func generateCodingKeysEnum(context: some MacroExpansionContext) -> EnumDeclSyntax {
        let uniqueAssociatedValues = self.cases.reduce(into: Set<String>()) { codingKeys, enumCase in
            if let associatedValues = enumCase.associatedValues {
                for associatedValue in associatedValues {
                    codingKeys.insert(associatedValue.firstName.text)
                }
            }
        }

        return try! EnumDeclSyntax("private enum CodingKeys: String, CodingKey") {
            try MemberDeclListItemSyntax(decl: EnumCaseDeclSyntax {
                EnumCaseElementSyntax(identifier: "type")

                for associatedValue in uniqueAssociatedValues {
                    try EnumCaseElementSyntax(identifier: TokenSyntax(validating: .identifier(associatedValue)))
                }
            })
        }
    }

    func generateEncodeFunction(context: some MacroExpansionContext) -> FunctionDeclSyntax {
        let encodeCases = self.cases.map { enumCase -> SwitchCaseSyntax in
            let encodeLabel = SwitchCaseLabelSyntax {
                if let tupleExpression = enumCase.tupleExpression {
                    CaseItemSyntax(pattern: ExpressionPatternSyntax(expression: FunctionCallExprSyntax(
                        calledExpression: MemberAccessExprSyntax(name: enumCase.identifier),
                        leftParen: .leftParenToken(),
                        argumentList: tupleExpression.elementList,
                        rightParen: .rightParenToken()
                    )))
                } else {
                    CaseItemSyntax(pattern: ExpressionPatternSyntax(expression: MemberAccessExprSyntax(name: enumCase.identifier)))
                }
            }

            return SwitchCaseSyntax(label: .case(encodeLabel), statements: CodeBlockItemListSyntax {
                "try container.encode(SubType.\(enumCase.identifier), forKey: .type)"

                if let associatedValues = enumCase.associatedValues {
                    for associatedValue in associatedValues {
                        "try container.encode(\(associatedValue.firstName), forKey: .\(associatedValue.firstName))"
                    }
                }
            })
        }

        return try! FunctionDeclSyntax("public func encode(to encoder: Encoder) throws") {
            "var container = encoder.container(keyedBy: CodingKeys.self)"

            SwitchExprSyntax(expression: "self" as ExprSyntax) {
                for encodeCase in encodeCases {
                    encodeCase
                }
            }
        }
    }

    func generateDecodeInitializer(context: some MacroExpansionContext) -> InitializerDeclSyntax {
        let decodeCases = self.cases.map { enumCase -> SwitchCaseSyntax in
            let decodeLabel = SwitchCaseLabelSyntax {
                CaseItemSyntax(pattern: ExpressionPatternSyntax(expression: MemberAccessExprSyntax(name: enumCase.identifier)))
            }

            var decodeStatements = [CodeBlockItemSyntax]()
            
            if let associatedValues = enumCase.associatedValues {
                var caseWrap = ""
                var cases = [String]()

                for associatedValue in associatedValues {
                    decodeStatements.append("let \(associatedValue.firstName) = try container.decode(\(associatedValue.type).self, forKey: .\(associatedValue.firstName))")
                    cases.append("\(associatedValue.firstName): \(associatedValue.firstName)")
                }

                caseWrap.append("(")
                caseWrap.append(cases.joined(separator: ", "))
                caseWrap.append(")")
                decodeStatements.append("self = .\(enumCase.identifier)\(raw: caseWrap)")
            } else {
                decodeStatements.append("self = .\(enumCase.identifier)")
            }

            return SwitchCaseSyntax(
                label: .case(decodeLabel), 
                statements: CodeBlockItemListSyntax(decodeStatements)
            )
        }

        return try! InitializerDeclSyntax("public init(from decoder: Decoder) throws") {
            "let container = try decoder.container(keyedBy: CodingKeys.self)"
            "let subtype = try container.decode(SubType.self, forKey: .type)"

            SwitchExprSyntax(expression: "subtype" as ExprSyntax) {
                for decodeCase in decodeCases {
                    decodeCase
                }
            }
        }
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: declaration._syntaxNode,
                message: NotEnumDiagnosticMessage()
            ))
            return []
        }

        let enumCases: [EnumCase] = declaration.memberBlock.members.compactMap { member -> EnumCase? in
            guard
                let decl = member.as(MemberDeclListItemSyntax.self),
                let enumCase = decl.decl.as(EnumCaseDeclSyntax.self)
            else {
                return nil
            }

            return EnumCase(enumCase, in: context)
        }


        let macro = EnumCodableMacro(
            declaration: declaration,
            cases: enumCases
        )

        return [
            macro.generateSubTypeEnum(context: context).as(DeclSyntax.self),
            macro.generateCodingKeysEnum(context: context).as(DeclSyntax.self),
            macro.generateEncodeFunction(context: context).as(DeclSyntax.self),
            macro.generateDecodeInitializer(context: context).as(DeclSyntax.self),
        ]
    }
}
