import Compression
import XCTest
@testable import CofreKit

final class WorldsTests: XCTestCase {
    // A level.dat with every tag type the game writes; the old reader knew 4 and crashed the app on the rest.
    private func levelDat(name: String) -> Data {
        func s(_ x: String) -> [UInt8] { [UInt8(x.utf8.count >> 8), UInt8(x.utf8.count & 255)] + Array(x.utf8) }
        func tag(_ t: UInt8, _ k: String, _ payload: [UInt8]) -> [UInt8] { [t] + s(k) + payload }
        let version = tag(10, "Version", tag(3, "Id", [0, 0, 0x0f, 0xa0]) + tag(8, "Name", s("1.21.1")) + tag(1, "Snapshot", [0]) + [0])
        let data = tag(1, "hardcore", [0]) + tag(2, "SpawnY", [0, 64]) + tag(3, "GameType", [0, 0, 0, 1])
            + tag(4, "LastPlayed", [0, 0, 1, 0x92, 0x5d, 0x2a, 0x3c, 0x00]) + tag(5, "BorderSize", [0x4b, 0x18, 0x96, 0x80])
            + tag(6, "BorderCenterX", [0, 0, 0, 0, 0, 0, 0, 0]) + tag(7, "Bytes", [0, 0, 0, 2, 1, 2])
            + tag(9, "ServerBrands", [8, 0, 0, 0, 2] + s("vanilla") + s("neoforge")) + tag(11, "Ints", [0, 0, 0, 1, 0, 0, 0, 7])
            + tag(12, "Longs", [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8)) + version + tag(8, "LevelName", s(name)) + [0]
        let nbt = Data([10] + s("") + tag(10, "Data", data) + [0])
        // gzip: header, raw deflate, CRC (unchecked here) and size.
        var deflated = Data(count: nbt.count + 64)
        let n = deflated.withUnsafeMutableBytes { dst in
            nbt.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, nbt.count + 64,
                    src.bindMemory(to: UInt8.self).baseAddress!, nbt.count, nil, COMPRESSION_ZLIB)
            }
        }
        let size = UInt32(nbt.count)
        return Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255]) + deflated.prefix(n) + Data([0, 0, 0, 0])
            + Data([UInt8(size & 255), UInt8(size >> 8 & 255), UInt8(size >> 16 & 255), UInt8(size >> 24)])
    }

    func testWorldsListFromEveryTagTypeAndNeverCrashOnBadFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func world(_ folder: String, _ data: Data) throws {
            let dir = root.appendingPathComponent("saves/\(folder)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("level.dat"))
        }
        let good = levelDat(name: "My Base")
        try world("good", good)
        try world("truncated", good.prefix(good.count / 2))
        try world("garbage", Data([0x1f, 0x8b, 1, 2, 3]))
        let store = WorldStore(instance: Instance(id: "i", name: "i", gameDirectory: root, gameVersion: "1.21.1"))
        let worlds = try store.list()
        XCTAssertEqual(Set(worlds.map(\.folder)), ["good", "truncated", "garbage"])
        let base = try XCTUnwrap(worlds.first { $0.folder == "good" })
        XCTAssertEqual(base.displayName, "My Base")
        XCTAssertEqual(base.gameMode, "Creative")
        XCTAssertEqual(base.gameVersion, "1.21.1")
        XCTAssertNotNil(base.lastPlayed)
        XCTAssertEqual(worlds.first { $0.folder == "garbage" }?.displayName, "garbage", "unreadable worlds show their folder")
    }
}
