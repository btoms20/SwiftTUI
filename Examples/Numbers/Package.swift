// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Numbers",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "Numbers",
            dependencies: ["SwiftTUI"]),
        .testTarget(
            name: "NumbersTests",
            dependencies: ["Numbers"]),
    ]
)
