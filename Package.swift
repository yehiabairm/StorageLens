// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StorageLens",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StorageLensCore"),
        .executableTarget(name: "StorageLens", dependencies: ["StorageLensCore"]),
        .testTarget(name: "StorageLensCoreTests", dependencies: ["StorageLensCore"]),
    ]
)
