// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BuddyCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "BuddyCore", targets: ["BuddyCore"])],
    targets: [
        .target(name: "BuddyCore", path: "Shared/Core"),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"], path: "Tests/BuddyCoreTests")
    ]
)
