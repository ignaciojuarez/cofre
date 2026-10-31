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

    func testRepairLibrariesRemovesEmptyFileBlockingMavenFolder() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let libraries = root.appendingPathComponent("libraries")
        let jar = libraries.appendingPathComponent("org/ow2/asm/asm/9.7/asm-9.7.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: jar)
        try Data().write(to: libraries.appendingPathComponent("net"))
        XCTAssertEqual(store.repairLibraries().map(\.lastPathComponent), ["net"])
        try FileManager.default.createDirectory(at: libraries.appendingPathComponent("net/minecraft"), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jar.path))
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
                "Requested Neo": ["name": "Requested Neo", "lastVersionId": "1.21.1", "cofreRequestedLoader": "neoforge"],
            ],
        ]
        try JSONSerialization.data(withJSONObject: profiles).write(to: root.appendingPathComponent("launcher_profiles.json"))
        try writeVersion(root: root, id: "fabric-loader-0.20.1-26.3", game: "26.3", library: "net.fabricmc:fabric-loader:0.20.1")
        try writeVersion(root: root, id: "neoforge-21.1.77", game: "1.21.1", library: "net.neoforged:neoforge:21.1.77")
        try writeVersion(root: root, id: "1.20.1-forge-47.1.106", game: "1.20.1", library: "net.neoforged:forge:1.20.1-47.1.106")
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
        let oldNeo = try XCTUnwrap(byName["Old Neo"])
        XCTAssertEqual(oldNeo.loader, .neoforge, "early NeoForge has a Forge-shaped id")
        XCTAssertTrue(oldNeo.loader.isInstalled(in: oldNeo.versionID, root: root, minecraftVersion: oldNeo.gameVersion))
        XCTAssertEqual(byName["Requested Neo"]?.loader, .neoforge)
        let requested = try XCTUnwrap(byName["Requested Neo"])
        XCTAssertFalse(requested.loader.isInstalled(in: requested.versionID, root: root, minecraftVersion: requested.gameVersion))
        XCTAssertEqual(store.lastPlayedID, "Fabric Mods")
    }

    func testCreateKeepsPlainVersionForTheLoaderInstaller() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let i = try store.create(name: "New Neo", version: "1.20.1", loader: .neoforge, loaderVersion: "47.1.106")
        XCTAssertEqual(i.versionID, "1.20.1", "no made-up neoforge-loader-… id; Air's installer writes the real one")
        XCTAssertEqual(i.loader, .neoforge)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("launcher_profiles.json"))) as? [String: Any])
        let profile = try XCTUnwrap((document["profiles"] as? [String: Any])?[i.id] as? [String: Any])
        XCTAssertEqual(profile["cofreRequestedLoader"] as? String, "neoforge")
        XCTAssertFalse(Instance.Loader.neoforge.isInstalled(in: i.versionID, root: root, minecraftVersion: "1.20.1"))
    }

    private func writeVersion(root: URL, id: String, game: String, library: String) throws {
        let folder = root.appendingPathComponent("versions/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let profile: [String: Any] = ["id": id, "inheritsFrom": game,
            "mainClass": "net.minecraft.launchwrapper.Launch", "libraries": [["name": library]]]
        try JSONSerialization.data(withJSONObject: profile).write(to: folder.appendingPathComponent("\(id).json"))
    }

    func testEverySupportedLoaderRequiresInstalledVersionEvidence() throws {
        let (_, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(Instance.Loader, String, String)] = [
            (.fabric, "fabric-loader-0.16.9-1.21.1", "net.fabricmc:fabric-loader:0.16.9"),
            (.quilt, "quilt-loader-0.27.0-1.21.1", "org.quiltmc:quilt-loader:0.27.0"),
            (.forge, "1.21.1-forge-52.0.1", "net.minecraftforge:forge:1.21.1-52.0.1"),
            (.neoforge, "neoforge-21.1.77", "net.neoforged:neoforge:21.1.77"),
            (.neoforge, "1.20.1-forge-47.1.106", "net.neoforged:forge:1.20.1-47.1.106"),
        ]
        for (loader, id, library) in cases {
            XCTAssertFalse(loader.isInstalled(in: id, root: root, minecraftVersion: "1.21.1"), id)
            let game = id == "1.20.1-forge-47.1.106" ? "1.20.1" : "1.21.1"
            try writeVersion(root: root, id: id, game: game, library: library)
            XCTAssertTrue(loader.isInstalled(in: id, root: root, minecraftVersion: game), id)
            XCTAssertFalse(loader.isInstalled(in: id, root: root, minecraftVersion: "26.3"), id)
            XCTAssertFalse(Instance.Loader.unknown.isInstalled(in: id, root: root, minecraftVersion: game), id)
        }
    }

    func testLoaderRejectsInvalidIncompleteOrWrongVersionJSON() throws {
        let (_, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = "1.20.1-forge-47.1.106"
        try writeVersion(root: root, id: id, game: "1.20.1", library: "net.neoforged:forge:1.20.1-47.1.106")
        let url = root.appendingPathComponent("versions/\(id)/\(id).json")
        let good = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var variants: [[String: Any]] = []
        for field in ["id", "inheritsFrom", "mainClass", "libraries"] {
            var bad = good; bad.removeValue(forKey: field); variants.append(bad)
        }
        var wrongID = good; wrongID["id"] = "different"; variants.append(wrongID)
        var wrongLoader = good; wrongLoader["libraries"] = [["name": "net.minecraftforge:forge:1.20.1-47.1.106"]]; variants.append(wrongLoader)
        var noLoader = good; noLoader["libraries"] = []; variants.append(noLoader)
        var emptyMain = good; emptyMain["mainClass"] = ""; variants.append(emptyMain)
        for bad in variants {
            try JSONSerialization.data(withJSONObject: bad).write(to: url)
            XCTAssertFalse(Instance.Loader.neoforge.isInstalled(in: id, root: root, minecraftVersion: "1.20.1"))
        }
        try Data("not JSON".utf8).write(to: url)
        XCTAssertFalse(Instance.Loader.neoforge.isInstalled(in: id, root: root, minecraftVersion: "1.20.1"))
        for unsafeID in ["../escape", ".", "..", "", "nested/profile"] {
            XCTAssertFalse(Instance.Loader.neoforge.isInstalled(in: unsafeID, root: root, minecraftVersion: "1.20.1"))
        }
    }

    func testExplicitUnknownLoaderFailsClosedAndCanonicalRequestWins() throws {
        let (store, root) = try airFixture(); defer { try? FileManager.default.removeItem(at: root) }
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.profilesURL)) as? [String: Any])
        var profiles = try XCTUnwrap(document["profiles"] as? [String: [String: Any]])
        profiles["Unknown"] = ["name": "Unknown", "lastVersionId": "neoforge-21.1.77", "cofreRequestedLoader": "futureloader"]
        profiles["Canonical"] = ["name": "Canonical", "lastVersionId": "1.20.1-forge-47.1.106", "cofreRequestedLoader": "neoforge", "loader": "forge"]
        document["profiles"] = profiles
        try JSONSerialization.data(withJSONObject: document).write(to: store.profilesURL)
        let instances = try store.list()
        XCTAssertEqual(instances.first { $0.name == "Unknown" }?.loader, .unknown)
        XCTAssertEqual(instances.first { $0.name == "Canonical" }?.loader, .neoforge)
        XCTAssertEqual(Instance.Loader.resolve(requested: nil, legacy: "futureloader", versionID: "fabric-loader-0.16.9-1.21.1"), .unknown)
    }

    func testJVMUseAffectsEveryInstanceAndSurvivesSameProcessReload() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.create(name: "Other", version: "1.20.1")
        XCTAssertTrue(try store.list().allSatisfy { !$0.restartRequired })
        try store.markJVMUsed()
        let reloaded = try InstanceStore(root: root)
        XCTAssertEqual(try reloaded.list().count, 2)
        XCTAssertTrue(try reloaded.list().allSatisfy { $0.restartRequired && $0.restartSession == Instance.currentSession })
        XCTAssertTrue(try reloaded.create(name: "Created after Java", version: "1.21.1").restartRequired)
    }

    func testPriorProcessJVMMarkerExpiresWithoutRewritingFiles() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.markJVMUsed()
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.profilesURL)) as? [String: Any])
        document["cofreJVMUseSession"] = "previous-process"
        let stale = try JSONSerialization.data(withJSONObject: document)
        try stale.write(to: store.profilesURL)
        XCTAssertTrue(try InstanceStore(root: root).list().allSatisfy { !$0.restartRequired })
        XCTAssertEqual(try Data(contentsOf: store.profilesURL), stale)
        var instance = try XCTUnwrap(store.list().first)
        instance.restartSession = Instance.currentSession
        XCTAssertTrue(instance.restartRequired)
        instance.restartSession = "previous-process"
        XCTAssertFalse(instance.restartRequired)
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
