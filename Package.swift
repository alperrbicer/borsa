// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BorsaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BorsaCore", targets: ["BorsaCore"])],
    targets: [
        .target(name: "BorsaCore"),
        .testTarget(name: "BorsaCoreTests", dependencies: ["BorsaCore"])
    ]
)
