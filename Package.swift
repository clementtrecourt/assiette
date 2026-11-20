// swift-tools-version:5.9
// The adaptive engine (App/Sources/Engine) as a standalone package, so it can be built and
// tested on Linux with `swift test`. The iOS app compiles the same files directly (project.yml).
import PackageDescription

let package = Package(
    name: "AssietteEngine",
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        .target(name: "AssietteEngine", path: "App/Sources/Engine"),
        .testTarget(name: "AssietteEngineTests", dependencies: ["AssietteEngine"], path: "EngineTests"),
    ]
)
