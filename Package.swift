// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rocket",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rocket", targets: ["RocketApp"]),
        .executable(name: "rocketd", targets: ["rocketd"]),
        .executable(name: "rocket", targets: ["RocketCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Domain layer: models, state machine, ports. No third-party, no AppKit/SwiftUI.
        .target(name: "RocketCore"),
        // Engine: scheduler, coordinators, segmentation. Depends on Core only.
        .target(name: "RocketEngine", dependencies: ["RocketCore"]),
        // Adapters
        .target(name: "RocketNetworking", dependencies: ["RocketCore"]),
        .target(
            name: "RocketPersistence",
            dependencies: ["RocketCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "RocketIPC", dependencies: ["RocketCore"]),
        // UI layer
        .target(name: "RocketDesign"),

        // Processes (composition roots)
        .executableTarget(
            name: "RocketApp",
            dependencies: ["RocketCore", "RocketIPC", "RocketDesign"],
            path: "App"
        ),
        .executableTarget(
            name: "rocketd",
            dependencies: ["RocketCore", "RocketEngine", "RocketNetworking", "RocketPersistence", "RocketIPC"],
            path: "Agent"
        ),
        .executableTarget(
            name: "RocketCLI",
            dependencies: ["RocketIPC", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),

        .testTarget(name: "RocketCoreTests", dependencies: ["RocketCore"]),
        .testTarget(name: "RocketPersistenceTests", dependencies: ["RocketPersistence"]),
        .testTarget(name: "RocketIPCTests", dependencies: ["RocketIPC"]),
    ]
)
