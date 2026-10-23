// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EyeRest",
    platforms: [.macOS(.v14)],
    targets: [
        // The break timer's logic and activity log, free of UI and system calls so it can be tested.
        .target(name: "EyeRestCore", path: "Sources/EyeRestCore"),
        .executableTarget(name: "EyeRest", dependencies: ["EyeRestCore"], path: "Sources/EyeRest"),
        // A read-only MCP server over the activity log, bundled into the app.
        .target(name: "EyeRestMCP", dependencies: ["EyeRestCore"], path: "Sources/EyeRestMCP"),
        .executableTarget(name: "eyerest-mcp", dependencies: ["EyeRestCore", "EyeRestMCP"], path: "Sources/eyerest-mcp"),
        .testTarget(name: "EyeRestCoreTests", dependencies: ["EyeRestCore"], path: "Tests/EyeRestCoreTests"),
        .testTarget(name: "EyeRestMCPTests", dependencies: ["EyeRestCore", "EyeRestMCP"], path: "Tests/EyeRestMCPTests"),
    ]
)
