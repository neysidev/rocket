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

        // The app and rocketd are built by Rocket.xcodeproj (see project.yml); the CLI builds here too for `swift run rocket`.
        .executableTarget(
            name: "RocketCLI",
            dependencies: ["RocketIPC", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),

        .testTarget(name: "RocketCoreTests", dependencies: ["RocketCore"]),
        .testTarget(name: "RocketPersistenceTests", dependencies: ["RocketPersistence"]),
        .testTarget(name: "RocketIPCTests", dependencies: ["RocketIPC"]),
    ]
)
