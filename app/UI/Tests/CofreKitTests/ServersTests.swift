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

extension CofreServerEngineTests {
    @MainActor func testFixtureListAddRemoveCopyAndRunningGuard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CofreServersStore(gameDirectory: root)
        // Independent, uncompressed Java NBT fixture: root {servers:[{name:"A",ip:"x"}]}.
        let fixture = Data([10,0,0,9,0,7,115,101,114,118,101,114,115,10,0,0,0,1,
                            8,0,4,110,97,109,101,0,1,65,8,0,2,105,112,0,1,120,0,0])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try fixture.write(to: source.fileURL)
        XCTAssertEqual(try source.list().map(\.ip), ["x"])
        let record = CofreServerRecord(name: "B", ip: "b.local", icon: Data([1, 2]), acceptTextures: 1,
                                     unknown: [("number", .raw(3, Data([0, 0, 0, 42]))), ("nested", .list([.compound([("x", .string("y"))])]))])
        XCTAssertEqual(try source.add(record), 1)
        XCTAssertEqual(try source.add(record), 1)
        let target = CofreServersStore(gameDirectory: root.appendingPathComponent("target"))
        let id = CofreServersStore.id(index: 1, record: record)
        try source.copy(id: id, to: target)
        let copied = try XCTUnwrap(target.list().first)
        XCTAssertEqual(copied.icon, record.icon); XCTAssertEqual(copied.acceptTextures, 1)
        XCTAssertEqual(ServersDatCodec.encode([copied]), ServersDatCodec.encode([record]))
        try source.remove(id: id)
        XCTAssertEqual(try source.list().map(\.ip), ["x"])
        XCTAssertThrowsError(try source.remove(id: id))
        let blocked = CofreServersStore(gameDirectory: root, isGameRunning: { true })
        let before = try Data(contentsOf: source.fileURL)
        XCTAssertThrowsError(try blocked.add(record))
        XCTAssertThrowsError(try blocked.remove(at: 0))
        XCTAssertThrowsError(try target.copy(id: CofreServersStore.id(index: 0, record: copied), to: blocked))
        XCTAssertEqual(try Data(contentsOf: source.fileURL), before)
    }
    @MainActor func testCorruptionCannotBeOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = CofreServersStore(gameDirectory: root)
        let corrupt = Data([10,0,0,9,0,7,115])
        try corrupt.write(to: store.fileURL)
        XCTAssertThrowsError(try store.list())
        XCTAssertThrowsError(try store.add(.init(name: "x", ip: "x")))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
        let encoded = ServersDatCodec.encode([.init(name: "x", ip: "x")])
        for size in 0..<encoded.count { XCTAssertThrowsError(try ServersDatCodec.decode(encoded.prefix(size))) }
    }
    func testSRVWireParsingAndInvalidRecords() {
        let data = Data([0,10,0,20,99,221,4] + Array("play".utf8) + [7] + Array("example".utf8) + [3] + Array("org".utf8) + [0])
        let record = MinecraftSRV.parse(data)
        XCTAssertEqual(record?.host, "play.example.org"); XCTAssertEqual(record?.port, 25565)
        XCTAssertEqual(record?.priority, 10); XCTAssertEqual(record?.weight, 20)
        for size in 0..<data.count { XCTAssertNil(MinecraftSRV.parse(data.prefix(size))) }
        XCTAssertNil(MinecraftSRV.parse(Data([0,0,0,0,99,221,0])))
        XCTAssertNil(MinecraftSRV.parse(Data([0,0,0,0,99,221,192,12])))
    }
    func testStatusPacketIncludesJSONStringLength() throws {
        let json = Data(#"{"description":"Hi","players":{"online":3}}"#.utf8)
        let packet = Data([0, UInt8(json.count)]) + json
        XCTAssertEqual(try MinecraftServerPinger.statusObject(packet)["description"] as? String, "Hi")
        XCTAssertThrowsError(try MinecraftServerPinger.statusObject(Data([0, 255, 255, 255, 255, 255])))
    }
    func testJoinArgsPreserveSRVNameIPv6AndWorldSpaces() {
        XCTAssertEqual(MinecraftLaunchArguments.server(.init(host: "srv.example.org"), gameVersion: "26.3"), ["--quickPlayMultiplayer", "srv.example.org"])
        XCTAssertEqual(MinecraftLaunchArguments.server(.init(host: "::1", port: 25566), gameVersion: "1.20"), ["--quickPlayMultiplayer", "[::1]:25566"])
        XCTAssertEqual(MinecraftLaunchArguments.singleplayer(folder: "My World", gameVersion: "26.3"), ["--quickPlaySingleplayer", "My World"])
        for value in ["host:0", "host:65536", "host:bad", "[::1]junk", "[::1", "a b", ":25565"] { XCTAssertNil(MinecraftServerAddress.parse(value)) }
    }
    func testDirectoryFiltersVersionLoaderAndSaved() throws {
        let data = Data(#"{"hits":[{"project_id":"a","name":"A","summary":"hello","game_versions":["1.21.1"],"mrpack_loaders":["fabric"],"minecraft_java_server":{"address":"a.net","ping":{"data":{"players_online":3,"players_max":10}}}},{"project_id":"b","name":"B","summary":"hi","game_versions":["1.21.1"],"minecraft_java_server":{"address":"b.net"}}]}"#.utf8)
        XCTAssertEqual(try ServerDirectory.decode(data, version: "1.21.1", loader: "fabric", saved: []).map(\.address), ["a.net", "b.net"])
        XCTAssertEqual(try ServerDirectory.decode(data, version: "1.21.1", loader: "forge", saved: []).map(\.address), ["b.net"])
        XCTAssertTrue(try ServerDirectory.decode(data, version: "1.21.1", loader: "forge", saved: ["B.NET"]).isEmpty)
        XCTAssertTrue(try ServerDirectory.decode(data, version: "1.20.1", loader: "fabric", saved: []).isEmpty)
    }
}
