// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EyeRest",
    platforms: [.macOS(.v14)],
    targets: [
        // The break timer's logic, free of UI and system calls so it can be tested.
        .target(name: "EyeRestCore", path: "Sources/EyeRestCore"),
        .executableTarget(name: "EyeRest", dependencies: ["EyeRestCore"], path: "Sources/EyeRest"),
        .testTarget(name: "EyeRestCoreTests", dependencies: ["EyeRestCore"], path: "Tests/EyeRestCoreTests"),
    ]
)
