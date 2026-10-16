// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Transom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Transom", path: "Sources/Transom"),
        .testTarget(name: "TransomTests", dependencies: ["Transom"], path: "Tests/TransomTests")
    ]
)
