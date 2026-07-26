// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Flush",
    products: [
        .library(name: "FlushCore", targets: ["FlushCore"]),
        .library(name: "FlushMetrics", targets: ["FlushMetrics"]),
        .executable(name: "flush", targets: ["FlushCLI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "603.0.0"
        )
    ],
    targets: [
        .target(
            name: "FlushCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .target(
            name: "FlushMetrics",
            dependencies: ["FlushCore"]
        ),
        .executableTarget(
            name: "FlushCLI",
            dependencies: ["FlushCore", "FlushMetrics"]
        ),
        .testTarget(
            name: "FlushCoreTests",
            dependencies: ["FlushCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FlushMetricsTests",
            dependencies: ["FlushMetrics"]
        )
    ]
)
