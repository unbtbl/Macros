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

    func testBasicExpansion() {
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
            protocol MyDependencyProtocol : AnyObject {
                func foo() -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: () -> String = unimplemented()
                func foo() -> String {
                    return _foo()
                }
                init(foo: @escaping () -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testPublicExpansion() {
        assertMacroExpansion(
            """
            @AutoDependency
            public final class MyDependency {
                public func foo() -> String {
                    return "bar"
                }
                func cantTouchMe() {}
            }
            """,
            expandedSource: """
            public final class MyDependency {
                public func foo() -> String {
                    return "bar"
                }
                func cantTouchMe() {
                }
            }
            public protocol MyDependencyProtocol : AnyObject {
                func foo() -> String
            }
            open class MyDependencyMock: MyDependencyProtocol {
                var _foo: () -> String = unimplemented()
                public func foo() -> String {
                    return _foo()
                }
                public init(foo: @escaping () -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testForDumpingSyntaxTree() throws {
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
