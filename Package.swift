// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "whistle",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WhistleCore"),
        .executableTarget(name: "whistle", dependencies: ["WhistleCore"]),
        .executableTarget(name: "whistle-tests", dependencies: ["WhistleCore"]),
    ]
)