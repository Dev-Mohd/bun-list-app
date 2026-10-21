// swift-tools-version: 6.0
import PackageDescription

// Product rules only. This package must not import SwiftUI, UIKit, SwiftData or other Apple-only
// frameworks so `swift test` runs the same rules on Linux and on macOS.
let package = Package(
    name: "BunnListCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BunnListCore", targets: ["BunnListCore"])],
    targets: [
        .target(name: "BunnListCore", resources: [.process("Resources")]),
        .testTarget(name: "BunnListCoreTests", dependencies: ["BunnListCore"])
    ],
    swiftLanguageModes: [.v5]
)
