// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TabType",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TabType", path: "TabType")
    ]
)
