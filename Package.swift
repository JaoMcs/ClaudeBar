// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeBarCore"),
        .executableTarget(name: "ClaudeBar", dependencies: ["ClaudeBarCore"]),
        .executableTarget(name: "claudebar-hook", dependencies: ["ClaudeBarCore"]),
        .testTarget(name: "ClaudeBarTests", dependencies: ["ClaudeBar", "ClaudeBarCore"]),
    ]
)
