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
                var meNeither = 0
            }
            """,
            expandedSource: """
            public final class MyDependency {
                public func foo() -> String {
                    return "bar"
                }
                func cantTouchMe() {
                }
                var meNeither = 0
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

    func testMultipleRequirements() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo() -> String {
                    return "bar"
                }
                func bar() -> String {
                    return "foo"
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo() -> String {
                    return "bar"
                }
                func bar() -> String {
                    return "foo"
                }
            }
            protocol MyDependencyProtocol : AnyObject {
                func foo() -> String
                func bar() -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: () -> String = unimplemented()
                func foo() -> String {
                    return _foo()
                }
                var _bar: () -> String = unimplemented()
                func bar() -> String {
                    return _bar()
                }
                init(foo: @escaping () -> String = unimplemented(), bar: @escaping () -> String = unimplemented()) {
                    self._foo = foo
                    self._bar = bar
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testFunctionWithParameter() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo(bar: String) -> String {
                    return bar
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo(bar: String) -> String {
                    return bar
                }
            }
            protocol MyDependencyProtocol : AnyObject {
                func foo(bar: String) -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: (String) -> String = unimplemented()
                func foo(bar: String) -> String {
                    return _foo(bar)
                }
                init(foo: @escaping (String) -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testFunctionWithMultipleParameters() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo(bar: String, baz: Int) -> String {
                    return bar
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo(bar: String, baz: Int) -> String {
                    return bar
                }
            }
            protocol MyDependencyProtocol : AnyObject {
                func foo(bar: String, baz: Int) -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: (String, Int) -> String = unimplemented()
                func foo(bar: String, baz: Int) -> String {
                    return _foo(bar, baz)
                }
                init(foo: @escaping (String, Int) -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }
    
    func testAsyncFunction() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo(bar: String, baz: Int) async -> String {
                    return bar
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo(bar: String, baz: Int) async -> String {
                    return bar
                }
            }
            protocol MyDependencyProtocol : AnyObject {
                func foo(bar: String, baz: Int) async -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: (String, Int) async -> String = unimplemented()
                func foo(bar: String, baz: Int) async -> String {
                    return await _foo(bar, baz)
                }
                init(foo: @escaping (String, Int) async -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testThrowingFunction() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo(bar: String, baz: Int) throws -> String {
                    return bar
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo(bar: String, baz: Int) throws -> String {
                    return bar
                }
            }
            protocol MyDependencyProtocol : AnyObject {
                func foo(bar: String, baz: Int) throws -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: (String, Int) throws -> String = unimplemented()
                func foo(bar: String, baz: Int) throws -> String {
                    return try _foo(bar, baz)
                }
                init(foo: @escaping (String, Int) throws -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }

    func testAsyncThrowingFunction() {
        assertMacroExpansion(
            """
            @AutoDependency
            final class MyDependency {
                func foo(bar: String, baz: Int) async throws -> String {
                    return bar
                }
            }
            """,
            expandedSource: """
            final class MyDependency {
                func foo(bar: String, baz: Int) async throws -> String {
                    return bar
                }
            }
            protocol MyDependencyProtocol : AnyObject {
                func foo(bar: String, baz: Int) async throws -> String
            }
            class MyDependencyMock: MyDependencyProtocol {
                var _foo: (String, Int) async throws -> String = unimplemented()
                func foo(bar: String, baz: Int) async throws -> String {
                    return try await _foo(bar, baz)
                }
                init(foo: @escaping (String, Int) async throws -> String = unimplemented()) {
                    self._foo = foo
                }
            }
            extension MyDependency: MyDependencyProtocol {
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }
}
