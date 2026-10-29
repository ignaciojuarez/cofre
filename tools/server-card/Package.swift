// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "server-card", platforms: [.macOS(.v14)], products: [.executable(name: "server-card", targets: ["server-card"])], targets: [.executableTarget(name: "server-card")])
