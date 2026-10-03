// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftTUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftTUI",
            targets: ["SwiftTUI"]),
    ],
    dependencies: [
         .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SwiftTUI",
            dependencies: [],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "SwiftTUITests",
            dependencies: ["SwiftTUI", "SwiftTUITestApp"],
            swiftSettings: swiftSettings),
        // Run in a pseudo-terminal by the end-to-end tests; not part of any product.
        .executableTarget(
            name: "SwiftTUITestApp",
            dependencies: ["SwiftTUI"],
            path: "Tests/SwiftTUITestApp",
            swiftSettings: swiftSettings),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]
}
