// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GremlinKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GremlinKit", targets: ["GremlinKit"])
    ],
    targets: [
        .target(name: "GremlinKit"),
        .testTarget(name: "GremlinKitTests", dependencies: ["GremlinKit"])
    ]
)
