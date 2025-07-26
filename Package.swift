// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyOverlayApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyOverlayApp",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            path: "Sources",
            sources: ["main.swift", "XPCConnectionManager.swift", "OverlayServiceProtocol.swift"]
        ),
        .executableTarget(
            name: "OverlayXPCService",
            dependencies: [],
            path: "Sources/OverlayXPCService",
            sources: ["main.swift"]
        ),
    ]
)
