// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClimateControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClimateControl", path: "Sources/ClimateControl"),
        .testTarget(name: "ClimateControlTests", dependencies: ["ClimateControl"], path: "Tests/ClimateControlTests"),
    ]
)
