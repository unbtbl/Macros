import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import DependenciesMacrosMacros

final class DependenciesMacrosTests: XCTestCase {
    // TODO: escaping sendable
    // TODO: private(set)
    // TODO: inits? -> skip
    // TODO: fileprivate
    // TODO: Public test case
    // TODO: some arguments
    // TODO: some return type
    // TODO: Protocol inheritance

    func testMacro() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo() -> String {
                    return "bar"
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo() -> String {
                    return "bar"
                }
            }
            protocol MyDependencyProtocol {
                func foo() -> String
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testForDumpingSyntaxTree() {
        assertMacroExpansion(
            """
            @DumpSyntax
            public protocol HenkProtocol {
                var isAdmin: Bool { get }
            }
            @DumpSyntax
            public class Henk {
                var implicit = Date(timeIntervalSinceReferenceDate: 200)
            }
            """,
            expandedSource: "",
            macros: ["DumpSyntax": DumpSyntaxMacro.self]
        )
    }
}

class Henk {
    var date = Date()
}
