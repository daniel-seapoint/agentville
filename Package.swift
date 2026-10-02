// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Agentville",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AgentvilleCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Agentville",
            dependencies: ["AgentvilleCore"],
            resources: [.copy("Resources/Logos")]
        ),
        .testTarget(
            name: "AgentvilleCoreTests",
            dependencies: ["AgentvilleCore"]
        ),
    ]
)
