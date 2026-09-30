// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ToDoList",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ToDoList",
            dependencies: ["SwiftTUI"]),
        .testTarget(
            name: "ToDoListTests",
            dependencies: ["ToDoList"]),
    ],
    swiftLanguageModes: [.v5]
)
