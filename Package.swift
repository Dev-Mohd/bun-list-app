// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BunnListCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "BunnListCore", targets: ["BunnListCore"])],
    targets: [
        .target(name: "BunnListCore", path: "BunnList/Core"),
        .testTarget(name: "BunnListCoreTests", dependencies: ["BunnListCore"], path: "Tests/BunnListCoreTests")
    ]
)
