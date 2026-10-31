// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CofreServerJoin", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CofreServerJoin", targets: ["CofreServerJoin"])],
    dependencies: [.package(path: "../UI")],
    targets: [
        .target(name: "CofreServerJoin", dependencies: [.product(name: "CofreKit", package: "UI")]),
        .testTarget(name: "CofreServerJoinTests", dependencies: ["CofreServerJoin"]),
    ])
