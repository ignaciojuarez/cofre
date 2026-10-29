// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CofreUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "CofreUI", targets: ["CofreUI"])],
    targets: [
        .target(
            name: "CofreUI",
            resources: [.copy("Resources/Fonts"), .copy("Resources/Images")]
        ),
        .testTarget(name: "CofreUITests", dependencies: ["CofreUI"]),
    ]
)
