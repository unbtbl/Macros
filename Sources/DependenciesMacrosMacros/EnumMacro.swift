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
                    TupleExprElementSyntax(expression: IdentifierExprSyntax(identifier: associatedValue.firstName))
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

        var encodeCases = [SwitchCaseSyntax]()
        var decodeCases = [SwitchCaseSyntax]()
        var decode = ""
        var codingKeys = Set<TokenSyntax>()
        var subtypes = Set<TokenSyntax>()
        codingKeys.insert("type")

        for enumCase in enumCases {
            subtypes.insert(enumCase.identifier)

            var caseUnwrap = ""

            if let associatedValues = enumCase.associatedValues {
                var cases = [String]()
                for associatedValue in associatedValues {
                    codingKeys.insert(associatedValue.firstName)
                    cases.append("let \(associatedValue.firstName)")
                }

                caseUnwrap.append("(")
                caseUnwrap.append(cases.joined(separator: ", "))
                caseUnwrap.append(")")
            }

            let encodeLabel = SwitchCaseLabelSyntax {
                if let tupleExpression = enumCase.tupleExpression {
                    CaseItemSyntax(pattern: ExpressionPatternSyntax(expression: FunctionCallExprSyntax(
                        calledExpression: MemberAccessExprSyntax(name: enumCase.identifier),
                        argumentList: tupleExpression.elementList
                    )))
                } else {
                    CaseItemSyntax(pattern: ExpressionPatternSyntax(expression: MemberAccessExprSyntax(name: enumCase.identifier)))
                }
            }

            encodeCases.append(SwitchCaseSyntax(label: .case(encodeLabel), statements: CodeBlockItemListSyntax {
                "try container.encode(SubType.\(enumCase.identifier), forKey: .type)"

                if let associatedValues = enumCase.associatedValues {
                    for associatedValue in associatedValues {
                        "try container.encode(\(associatedValue.firstName), forKey: .\(associatedValue.firstName))"
                    }
                }
            }))

            decode += """
            case .\(IdentifierExprSyntax(identifier: enumCase.identifier)):
            """

            if let associatedValues = enumCase.associatedValues {
                var caseWrap = ""
                var cases = [String]()

                for associatedValue in associatedValues {
                    decode += """
                    let \(associatedValue.firstName) = try container.decode(\(associatedValue.type).self, forKey: .\(associatedValue.firstName))
                    """

                    cases.append("\(associatedValue.firstName): \(associatedValue.firstName)")
                }

                caseWrap.append("(")
                caseWrap.append(cases.joined(separator: ", "))
                caseWrap.append(")")
                decode += """
                self = .\(enumCase.identifier)\(caseWrap)
                """
            } else {
                decode += """
                self = .\(enumCase.identifier)
                """
            }
        }

        let codingKeysCases = codingKeys.sorted(by: { $0.text > $1.text }).map { key in
            return EnumCaseDeclSyntax(elements: EnumCaseElementListSyntax {
                EnumCaseElementSyntax(identifier: key)
            })
        }

        let codingKeysDecl = EnumDeclSyntax("""
        private enum CodingKeys: String, CodingKey {
            \(raw: codingKeysCases)
        }
        """ as DeclSyntax)!

        let subtypeText = subtypes.sorted(by: { $0.text > $1.text }).map { subtype in
            return "case \(subtype)"
        }.joined(separator: "\n")

        let subtypeDecl = EnumDeclSyntax("""
        enum SubType: String, Codable {
            \(raw: subtypeText)
        }
        """ as DeclSyntax)!

        let encodeSwitch = SwitchExprSyntax(expression: IdentifierExprSyntax(identifier: "self"), cases: SwitchCaseListSyntax(encodeCases.map { .switchCase($0) }))
        let encodeDecl = FunctionDeclSyntax("""
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            \(encodeSwitch)
        }
        """ as DeclSyntax)!

        let decodeDecl = InitializerDeclSyntax("""
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let subtype = try container.decode(SubType.self, forKey: .type)

            switch subtype {
            \(raw: decode)
            }
        }
        """ as DeclSyntax)!

        return [
            subtypeDecl.as(DeclSyntax.self),
            codingKeysDecl.as(DeclSyntax.self),
            encodeDecl.as(DeclSyntax.self),
            decodeDecl.as(DeclSyntax.self),
        ]
    }
}