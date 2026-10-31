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
    dependencies: [
        // GitHub-flavoured Markdown → HTML for mod pages (the engine under Apple's swift-markdown).
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.9.0")
    ],
    targets: [
        // Cofre's own model of the game's files (instances, worlds, servers, content, accounts, downloads, logs).
        // Foundation only: no UIKit, no Air, so it runs and tests on the Mac.
        .target(
            name: "CofreKit",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            resources: [.copy("Resources/protocolVersions.json"), .copy("Resources/presets.json")]
        ),
        .target(
            name: "CofreUI",
            dependencies: ["CofreKit"],
            resources: [.copy("Resources/Fonts"), .copy("Resources/Images")]
        ),
        .testTarget(name: "CofreKitTests", dependencies: ["CofreKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CofreUITests", dependencies: ["CofreUI"]),
    ]
)
