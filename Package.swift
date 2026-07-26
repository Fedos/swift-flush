// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Flush",
    products: [
        .library(name: "FlushCore", targets: ["FlushCore"]),
        .library(name: "FlushMetrics", targets: ["FlushMetrics"]),
        .executable(name: "flush", targets: ["FlushCLI"])
    ],
    targets: [
        .target(name: "FlushCore"),
        .target(
            name: "FlushMetrics",
            dependencies: ["FlushCore"]
        ),
        .executableTarget(
            name: "FlushCLI",
            dependencies: ["FlushCore", "FlushMetrics"]
        ),
        .testTarget(
            name: "FlushMetricsTests",
            dependencies: ["FlushMetrics"]
        )
    ]
)
