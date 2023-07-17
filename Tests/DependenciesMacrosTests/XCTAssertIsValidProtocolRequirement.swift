import XCTest
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser
import SwiftParserDiagnostics
import SwiftBasicFormat
import Foundation

func XCTAssertIsValidProtocolRequirement(
    _ decl: DeclSyntax,
    file: StaticString = #file,
    line: UInt = #line
) {
    do {
        let protocolDecl = try ProtocolDeclSyntax("protocol Foo") {
            decl
        }
        let formatted = BasicFormat().rewrite(protocolDecl)

        // Try and compile the code using swiftc
        let source = formatted.description
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let sourceFile = tmpDir.appendingPathComponent("main.swift")
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)

        let standardError = Pipe()

        let process = Process()
        process.standardError = standardError
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", sourceFile.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
            XCTFail(
                "\(stderr.replacingOccurrences(of: sourceFile.path, with: ""))",
                file: file,
                line: line
            )
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

final class XCTAssertIsValidProtocolRequirementTests: XCTestCase {
    func testInvalidProtocolRequirement() {
       XCTExpectFailure {
            XCTAssertIsValidProtocolRequirement(
                """
                func foo() {
                    fatalError()
                }
                """
            )
       }
    }

    func testValidProtocolRequirement() {
        XCTAssertIsValidProtocolRequirement(
            """
            func foo()
            """
        )
    }
}