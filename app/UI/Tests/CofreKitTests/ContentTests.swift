import XCTest
@testable import CofreKit

final class ContentTests: XCTestCase {
    func testListToggleDeleteUndoAndInUse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("mods"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("resourcePacks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("shaderpacks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("saves/world/datapacks"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("mods/jei-19.1.jar")); try Data().write(to: root.appendingPathComponent("mods/old.jar.disabled"))
        try Data().write(to: root.appendingPathComponent("resourcePacks/Faithful-32.zip")); try Data().write(to: root.appendingPathComponent("shaderpacks/BSL.zip"))
        try Data().write(to: root.appendingPathComponent("saves/world/datapacks/test.zip"))
        try "resourcePacks:[\"vanilla\",\"file/Faithful-32.zip\"]\n".write(to: root.appendingPathComponent("options.txt"), atomically: true, encoding: .utf8)
        try "shaderPack=BSL.zip\n".write(to: root.appendingPathComponent("iris.properties"), atomically: true, encoding: .utf8)
        let store = ContentStore(gameDirectory: root)
        let mods = try store.list(.mods); XCTAssertEqual(mods.count, 2); XCTAssertFalse(mods.first { $0.id == "old.jar" }!.enabled)
        let pack = try XCTUnwrap(try store.list(.resourcePacks).first); XCTAssertTrue(pack.inUse)
        XCTAssertTrue(try store.list(.shaderpacks).first!.inUse)
        let mod = try XCTUnwrap(mods.first { $0.enabled }); try store.setEnabled(false, mod); XCTAssertFalse(try store.list(.mods).first { $0.id == mod.id }!.enabled)
        let token = try store.trash(pack); XCTAssertTrue(try store.list(.resourcePacks).isEmpty); try store.restore(token); XCTAssertEqual(try store.list(.resourcePacks).count, 1)
        XCTAssertEqual(try store.list(.datapacks).first?.world, "world")
        try? FileManager.default.removeItem(at: root)
    }
}
