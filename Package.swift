// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoeBalance",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LoeBalance", targets: ["LoeBalance"])],
    targets: [
        .executableTarget(name: "LoeBalance"),
        .testTarget(name: "LoeBalanceTests", dependencies: ["LoeBalance"])
    ]
)
