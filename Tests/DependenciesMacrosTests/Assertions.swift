import XCTest
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser
import SwiftParserDiagnostics
import SwiftBasicFormat
import Foundation
@testable import DependenciesMacrosMacros

func XCTAssert(
    _ decl: DeclSyntax,
    asProtocolRequirementEquals expected: DeclSyntax,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(
        try? decl.asProtocol(ProtocolRequirementConvertibleSyntax.self)?.asProtocolRequirement().as(DeclSyntax.self)?.trimmed.description,
        expected.trimmed.description,
        file: file,
        line: line
    )

    XCTAssertIsValidProtocolRequirement(
        expected,
        file: file,
        line: line
    )
}
