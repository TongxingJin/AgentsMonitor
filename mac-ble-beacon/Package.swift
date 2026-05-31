// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AgentStatusBLEBeacon",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AgentStatusBLEBeacon",
            path: "Sources/AgentStatusBLEBeacon",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
