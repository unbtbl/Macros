import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import DependenciesMacrosMacros

final class EnumCodableMacroTests: XCTestCase {
    func testMacro() {
        assertMacroExpansion(
            """
            @EnumCodable
            enum Role {
                case nobody
                case user(user: User)
                case admin(user: Admin)
            }
            """,
            expandedSource: """
            enum Role {
                case nobody
                case user(user: User)
                case admin(user: Admin)
                enum SubType: String, Codable {
                    case admin
                    case nobody
                    case user
                }
                private enum CodingKeys: String, CodingKey {
                    case type
                    case user
                }
                public func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                    case .nobody:
                        try container.encode(SubType.nobody, forKey: .type)
                    case .user(let user):
                        try container.encode(SubType.user, forKey: .type)
                        try container.encode(user, forKey: .user)
                    case .admin(let user):
                        try container.encode(SubType.admin, forKey: .type)
                        try container.encode(user, forKey: .user)
                    }
                }
            }
            """,
            macros: DependenciesMacrosPlugin.macros
        )
    }
}