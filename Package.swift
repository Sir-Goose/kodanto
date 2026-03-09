// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KodantoCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "KodantoCore",
            targets: ["KodantoCore"]
        )
    ],
    targets: [
        .target(
            name: "KodantoCore",
            path: "kodanto",
            exclude: [
                "App",
                "Assets.xcassets",
                "Views",
                "Core/OpenCodeAPIClient.swift",
                "Core/OpenCodeSSEClient.swift",
                "Core/SidecarProcess.swift"
            ],
            sources: [
                "Core/LiveSyncTracker.swift",
                "Models/OpenCodeModels.swift"
            ]
        ),
        .testTarget(
            name: "KodantoCoreTests",
            dependencies: ["KodantoCore"]
        )
    ]
)
