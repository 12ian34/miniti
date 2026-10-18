// swift-tools-version:5.10
import PackageDescription
let package = Package(
    name: "harness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.4")
    ],
    targets: [
        .executableTarget(name: "harness", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")], path: "Sources/harness")
    ]
)
