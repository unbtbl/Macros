// The Swift Programming Language
// https://docs.swift.org/swift-book

@_exported import Dependencies

@attached(peer, names: suffixed(Protocol), suffixed(Mock))
@attached(conformance)
public macro AutoDependency() = #externalMacro(module: "DependenciesMacrosMacros", type: "AutoDependencyMacro")