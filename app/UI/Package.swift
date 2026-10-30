// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CofreUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CofreUI", targets: ["CofreUI"]),
        .library(name: "CofreKit", targets: ["CofreKit"]),
    ],
    targets: [
        // Cofre's own model of the game's files (instances, worlds, servers, content, accounts, downloads, logs).
        // Foundation only: no UIKit, no Air, so it runs and tests on the Mac.
        .target(name: "CofreKit", resources: [.copy("Resources/protocolVersions.json")]),
        .target(
            name: "CofreUI",
            dependencies: ["CofreKit"],
            resources: [.copy("Resources/Fonts"), .copy("Resources/Images")]
        ),
        .testTarget(name: "CofreKitTests", dependencies: ["CofreKit"]),
        .testTarget(name: "CofreUITests", dependencies: ["CofreUI"]),
    ]
)
