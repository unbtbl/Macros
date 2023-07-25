import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
public struct DependenciesMacrosPlugin: CompilerPlugin {
    public static let macros: [String: Macro.Type] = [
        "AutoDependency": AutoDependency.self,
        "EnumCodable": EnumCodableMacro.self,
    ]

    public let providingMacros = Array(Self.macros.values)

    public init() {}
}