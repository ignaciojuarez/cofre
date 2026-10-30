import XCTest
@testable import CofreKit

final class CofreServerEngineTests: XCTestCase {
    func testServersRoundTripPreservesFieldsAndUnknownTags() throws {
        let input = [CofreServerRecord(name: "A", ip: "example.org:25565", icon: Data([1,2,3]), acceptTextures: 1, hidden: true, unknown: [("future", .string("yes"))])]
        let output = try ServersDatCodec.decode(ServersDatCodec.encode(input)); XCTAssertEqual(output.count, 1); XCTAssertEqual(output[0].name, input[0].name); XCTAssertEqual(output[0].ip, input[0].ip); XCTAssertEqual(output[0].unknown.count, 1)
    }
    func testMotdFlattening() {
        XCTAssertEqual(MinecraftMOTD.flatten(["text": "Hi", "extra": [["text": " "] as [String: Any], ["text": "there"] as [String: Any]]]), "Hi there")
    }
    func testAddressAndArguments() {
        XCTAssertEqual(MinecraftServerAddress.parse("[::1]:25570"), .init(host: "::1", port: 25570))
        XCTAssertEqual(MinecraftServerAddress.parse("example.org")?.effectivePort, 25565)
        XCTAssertEqual(MinecraftLaunchArguments.server(.init(host: "x", port: 2), gameVersion: "1.20.1"), ["--quickPlayMultiplayer", "x:2"])
        XCTAssertEqual(MinecraftLaunchArguments.server(.init(host: "x", port: 2), gameVersion: "1.19.4"), ["--server", "x", "--port", "2"])
    }
}
