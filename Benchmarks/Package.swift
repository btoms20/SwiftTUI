// swift-tools-version: 6.2

// Kept as a separate package so SwiftTUI itself has no benchmark dependencies.
// Run with `swift package benchmark` from this directory.

import PackageDescription

let package = Package(
    name: "SwiftTUIBenchmarks",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.36.0"),
    ],
    targets: [
        .executableTarget(
            name: "Rendering",
            dependencies: [
                "SwiftTUI",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/Rendering",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        ),
    ]
)
