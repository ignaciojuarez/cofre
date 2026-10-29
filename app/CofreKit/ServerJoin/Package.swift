// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CofreServerJoin", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "CofreServerJoin", targets: ["CofreServerJoin"])], targets: [.target(name: "CofreServerJoin"), .testTarget(name: "CofreServerJoinTests", dependencies: ["CofreServerJoin"])])
