// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WacomBamboo",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BambooKit"),
        .executableTarget(name: "wacom-bamboo", dependencies: ["BambooKit"]),
        .testTarget(name: "BambooKitTests", dependencies: ["BambooKit"]),
    ]
)
