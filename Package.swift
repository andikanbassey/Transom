// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Drawer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Drawer", path: "Sources/Drawer")
    ]
)
