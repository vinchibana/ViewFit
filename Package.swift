// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ViewFit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ViewFit", targets: ["ViewFit"]),
        .executable(name: "ViewFitBridge", targets: ["ViewFitBridge"])
    ],
    targets: [
        .target(name: "ViewFitCore"),
        .executableTarget(name: "ViewFit", dependencies: ["ViewFitCore"]),
        .executableTarget(name: "ViewFitBridge", dependencies: ["ViewFitCore"]),
        .testTarget(name: "ViewFitCoreTests", dependencies: ["ViewFitCore"])
    ]
)
