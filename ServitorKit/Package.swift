// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ServitorKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ServitorKit", targets: ["ServitorKit"])
    ],
    targets: [
        .target(name: "ServitorKit"),
        .testTarget(name: "ServitorKitTests", dependencies: ["ServitorKit"])
    ]
)
