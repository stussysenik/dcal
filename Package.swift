// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "dcal",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // ── Domain Layer (pure logic, zero I/O, 100% testable) ──
        .target(
            name: "Domain",
            path: "Sources/Domain"
        ),

        // ── Application Layer (services, protocol-based DI) ──
        .target(
            name: "Application",
            dependencies: ["Domain"],
            path: "Sources/Application"
        ),

        // ── Infrastructure Layer (actor-based adapters) ──
        .target(
            name: "Infrastructure",
            dependencies: ["Domain", "Application"],
            path: "Sources/Infrastructure",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        // ── CLI (Swift ArgumentParser) ──
        .executableTarget(
            name: "dcal",
            dependencies: [
                "Domain",
                "Application",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CLI"
        ),

        // ── Tests ──
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain", "Application"],
            path: "Tests/DomainTests"
        ),
        .testTarget(
            name: "InfrastructureTests",
            dependencies: ["Infrastructure", "Application", "Domain"],
            path: "Tests/InfrastructureTests"
        ),
    ]
)
