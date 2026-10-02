// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WorkoutZonesCore", platforms: [.macOS(.v15)], products: [.library(name: "WorkoutZonesCore", targets: ["WorkoutZonesCore"])], targets: [.target(name: "WorkoutZonesCore", path: "Sources/Core"), .testTarget(name: "WorkoutZonesTests", dependencies: ["WorkoutZonesCore"], path: "Tests/Core")])
