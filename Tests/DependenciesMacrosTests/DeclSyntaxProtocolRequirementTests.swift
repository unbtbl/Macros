import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import DependenciesMacrosMacros

final class DeclSyntaxProtocolRequirementTests: XCTestCase {
    func testSimpleFunc() {
        XCTAssert(
            """
            func foo() {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo()"
        )
    }

    func testSimpleFuncWithWhereClause() {
        XCTAssert(
            """
            func foo<Input>(_ input: Input) where Input: CustomStringConvertible {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo<Input>(_ input: Input) where Input: CustomStringConvertible"
        )
    }

    func testSimpleFuncWithWhereClauseAndReturnType() {
        XCTAssert(
            """
            func foo() -> Int where Self: Foo {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo() -> Int where Self: Foo"
        )
    }

    func testSimpleFuncWithWhereClauseAndReturnTypeAndThrows() {
        XCTAssert(
            """
            func foo() throws -> Int where Self: Foo {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo() throws -> Int where Self: Foo"
        )
    }

    func testSimpleFuncWithWhereClauseAndReturnTypeAndThrowsAndAttributes() {
        XCTAssert(
            """
            @MainActor @Sendable func foo() throws -> Int where Self: Foo {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "@MainActor @Sendable func foo() throws -> Int where Self: Foo"
        )
    }

    func testAsyncFunc() {
        XCTAssert(
            """
            func foo() async {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo() async"
        )
    }

    func testAsyncFuncWithWhereClause() {
        XCTAssert(
            """
            func foo<Input>(_ input: Input) async where Input: CustomStringConvertible {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo<Input>(_ input: Input) async where Input: CustomStringConvertible"
        )
    }

    func testAsyncFuncWithWhereClauseAndReturnType() {
        XCTAssert(
            """
            func foo() async -> Int where Self: Foo {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo() async -> Int where Self: Foo"
        )
    }

    func testAsyncFuncWithWhereClauseAndReturnTypeAndThrows() {
        XCTAssert(
            """
            func foo() async throws -> Int where Self: Foo {
                fatalError()
            }
            """,
            asProtocolRequirementEquals: "func foo() async throws -> Int where Self: Foo"
        )
    }

    func testVar() {
        XCTAssert(
            """
            var foo: Int
            """,
            asProtocolRequirementEquals: "var foo: Int { get set }"
        )
    }

    func testLet() {
        XCTAssert(
            """
            let foo: Int
            """,
            asProtocolRequirementEquals: "var foo: Int { get }"
        )
    }

    func testPrivateSetVar() {
        XCTAssert(
            """
            private(set) var foo: Int
            """,
            asProtocolRequirementEquals: "var foo: Int { get }"
        )
    }

    func testComputedReadonlyVar() {
        XCTAssert(
            """
            var foo: Int {
                return 42
            }
            """,
            asProtocolRequirementEquals: "var foo: Int { get }"
        )
    }

    func testComputedVarWithSetter() {
        XCTAssert(
            """
            var foo: Int {
                get { return 42 }
                set { fatalError() }
            }
            """,
            asProtocolRequirementEquals: "var foo: Int { get set }"
        )
    }

    func testComputedVarWithExplicitGetter() {
        XCTAssert(
            """
            var foo: Int {
                get { return 42 }
            }
            """,
            asProtocolRequirementEquals: "var foo: Int { get }"
        )
    }

    func testAsyncGetter() {
        XCTAssert(
            """
            var foo: Int {
                get async { return 42 }
            }
            """,
            asProtocolRequirementEquals: "var foo: Int { get async }"
        )
    }

    func testAsyncThrowingGetter() {
        XCTAssert(
            """
            var foo: Int {
                get async throws { return 42 }
            }
            """,
            asProtocolRequirementEquals: "var foo: Int { get async throws }"
        )
    }
}
