// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rocket",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RocketCore", targets: ["RocketCore"]),
        .library(name: "RocketEngine", targets: ["RocketEngine"]),
        .library(name: "RocketNetworking", targets: ["RocketNetworking"]),
        .library(name: "RocketPersistence", targets: ["RocketPersistence"]),
        .library(name: "RocketIPC", targets: ["RocketIPC"]),
        .library(name: "RocketDesign", targets: ["RocketDesign"]),
        .library(name: "RocketUI", targets: ["RocketUI"]),
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
        // App screens and their view models; the app target is only the composition root.
        .target(
            name: "RocketUI",
            dependencies: ["RocketCore", "RocketIPC", "RocketNetworking", "RocketDesign"],
            resources: [.process("Resources")]
        ),

        // The app and rocketd are built by Rocket.xcodeproj (see project.yml); the CLI builds here too for `swift run rocket`.
        .executableTarget(
            name: "RocketCLI",
            dependencies: ["RocketIPC", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),

        // Development-only HTTP server for tests. Never ships.
        // Always optimized: byte generation is the bottleneck in debug builds.
        .target(name: "RocketTestServer", path: "Tests/RocketTestServer", swiftSettings: [.unsafeFlags(["-O"])]),
        .executableTarget(name: "rocket-test-server", dependencies: ["RocketTestServer"], path: "Tests/RocketTestServerTool"),

        .testTarget(name: "RocketCoreTests", dependencies: ["RocketCore"]),
        .testTarget(name: "RocketEngineTests", dependencies: ["RocketEngine", "RocketNetworking", "RocketTestServer"]),
        .testTarget(name: "RocketNetworkingTests", dependencies: ["RocketNetworking", "RocketTestServer"]),
        .testTarget(name: "RocketPersistenceTests", dependencies: ["RocketPersistence"]),
        .testTarget(name: "RocketIPCTests", dependencies: ["RocketIPC"]),
        .testTarget(name: "RocketUITests", dependencies: ["RocketUI"]),
    ]
)
