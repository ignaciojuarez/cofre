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

    /// Air's launcher_profiles.json as found on a device: profiles keyed by name, real version ids, relative folders.
    private func airFixture() throws -> (InstanceStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("cofre-instances/fab/mods"), withIntermediateDirectories: true)
        let profiles: [String: Any] = [
            "selectedProfile": "Fabric Mods",
            "profiles": [
                "(Default)": ["name": "(Default)", "lastVersionId": "latest-release"],
                "Fabric Mods": ["name": "Fabric Mods", "lastVersionId": "fabric-loader-0.20.1-26.3", "gameDir": "./cofre-instances/fab", "renderer": "libmetallum.dylib"],
                "Neo": ["name": "Neo", "lastVersionId": "neoforge-21.1.77"],
                "Old Neo": ["name": "Old Neo", "lastVersionId": "1.20.1-forge-47.1.106"],
            ],
        ]
        try JSONSerialization.data(withJSONObject: profiles).write(to: root.appendingPathComponent("launcher_profiles.json"))
        return (try InstanceStore(root: root), root)
    }

    func testReadsAirVersionIds() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let byName = Dictionary(uniqueKeysWithValues: try store.list().map { ($0.name, $0) })
        XCTAssertEqual(byName["Fabric Mods"]?.loader, .fabric)
        XCTAssertEqual(byName["Fabric Mods"]?.gameVersion, "26.3")
        XCTAssertEqual(byName["Fabric Mods"]?.gameDirectory.lastPathComponent, "fab")
        XCTAssertEqual(byName["Neo"]?.loader, .neoforge, "neoforge-… is never read as Forge")
        XCTAssertEqual(byName["Neo"]?.gameVersion, "1.21.1")
        XCTAssertEqual(byName["Old Neo"]?.gameVersion, "1.20.1")
        XCTAssertEqual(store.lastPlayedID, "Fabric Mods")
    }

    func testCreateKeepsPlainVersionForTheLoaderInstaller() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let i = try store.create(name: "New Neo", version: "1.20.1", loader: .neoforge, loaderVersion: "47.1.106")
        XCTAssertEqual(i.versionID, "1.20.1", "no made-up neoforge-loader-… id; Air's installer writes the real one")
        XCTAssertEqual(i.loader, .neoforge)
    }

    func testDeleteThenRestoreAfterRelaunchKeepsTheEngineProfile() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        var writes = 0
        store.didWriteProfiles = { writes += 1 }
        _ = try store.trash("Fabric Mods")
        XCTAssertGreaterThan(writes, 0, "the engine is told to reload")
        // A new store, as after Cofre restarts: no undo token, only Recently deleted.
        let later = try InstanceStore(root: root)
        let deleted = try XCTUnwrap(later.recentlyDeleted().first { $0.name == "Fabric Mods" })
        let restored = try later.restore(deleted)
        XCTAssertEqual(restored.versionID, "fabric-loader-0.20.1-26.3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.gameDirectory.appendingPathComponent("mods").path))
        XCTAssertTrue(later.recentlyDeleted().isEmpty)
    }

    func testDuplicateKeepsTheEngineProfile() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let copy = try store.duplicate("Fabric Mods")
        XCTAssertEqual(copy.versionID, "fabric-loader-0.20.1-26.3")
        XCTAssertEqual(copy.loader, .fabric)
    }

    func testRestoresAnEngineMadeFabricFolderWithNoMetadata() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("versions/fabric-loader-0.20.1-26.3"), withIntermediateDirectories: true)
        let folder = root.appendingPathComponent(".trash/450E7083-9D63-422D-9D04-216D3527DF7C-35B94B5B-4383-4269-A661-B919F645A9A3")
        try fm.createDirectory(at: folder.appendingPathComponent(".fabric"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("mods"), withIntermediateDirectories: true)
        let world = root.appendingPathComponent(".trash/world-1")
        try fm.createDirectory(at: world, withIntermediateDirectories: true)
        try Data().write(to: world.appendingPathComponent("level.dat"))
        let deleted = store.recentlyDeleted()
        XCTAssertEqual(deleted.count, 1, "deleted worlds aren't instances")
        let restored = try store.restore(try XCTUnwrap(deleted.first))
        XCTAssertEqual(restored.loader, .fabric)
        XCTAssertEqual(restored.versionID, "fabric-loader-0.20.1-26.3")
        XCTAssertEqual(restored.gameDirectory.lastPathComponent, "35B94B5B-4383-4269-A661-B919F645A9A3")
    }
}
