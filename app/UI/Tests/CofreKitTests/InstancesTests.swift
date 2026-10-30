import XCTest
@testable import CofreKit

final class InstancesTests: XCTestCase {
    private func fixture() throws -> (InstanceStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try InstanceStore(root: root)
        let i = try store.create(name: "Survival", version: "1.21.1")
        try FileManager.default.createDirectory(at: i.gameDirectory.appendingPathComponent("saves"), withIntermediateDirectories: true)
        try Data("world data".utf8).write(to: i.gameDirectory.appendingPathComponent("saves/world.txt"))
        return (store, root)
    }

    func testListAndDuplicatePreserveFiles() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let copy = try store.duplicate(try XCTUnwrap(store.list().first).id)
        XCTAssertEqual(try store.list().count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.gameDirectory.appendingPathComponent("saves/world.txt").path))
    }

    func testDeleteUndoRestoresProfileAndDirectory() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let instance = try XCTUnwrap(store.list().first)
        let token = try store.trash(instance.id)
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertEqual(try store.restore(token).name, "Survival")
        XCTAssertEqual(try store.list().count, 1)
    }

    func testExportImportRoundTrip() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try XCTUnwrap(store.list().first)
        let archive = try store.export(original.id, to: root.appendingPathComponent("backup.zip"))
        let imported = try store.import(archive, name: "Imported")
        XCTAssertEqual(imported.name, "Imported")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.gameDirectory.appendingPathComponent("saves/world.txt").path))
    }
}
