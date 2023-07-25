import DependenciesMacros
import Foundation

@EnumCodable
enum TestEnum: Codable {
    case user(name: String, age: Int)
    case admin(name: String, age: Int) 
}

let data = try JSONEncoder().encode(TestEnum.user(name: "test", age: 123))
print(String(data: data, encoding: .utf8)!)