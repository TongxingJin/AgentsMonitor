// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AgentStatusBeacon",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AgentStatusBeacon",
            path: "Sources/AgentStatusBeacon",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
