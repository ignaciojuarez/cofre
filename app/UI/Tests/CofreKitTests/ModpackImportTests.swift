import XCTest
@testable import CofreKit

final class ModpackImportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func zip(_ files: [String: String], name: String = "pack.zip") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Zip.write(files.sorted { $0.key < $1.key }.map { file in (path: file.key, data: { Data(file.value.utf8) }) }, to: url)
        return url
    }

    func testInterruptedImportRemovesOnlyNewFiles() throws {
        let existing = root.appendingPathComponent("options.txt")
        try Data("keep".utf8).write(to: existing)
        try ModpackImport.markImportStarted(in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("mods"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: root.appendingPathComponent("mods/new.jar"), options: .atomic)
        ModpackImport.cleanupAbandonedImport(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("mods/new.jar").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cofre-import-in-progress").path))
    }

    func testModrinthPackIsReadWithoutUnpacking() throws {
        let index = """
        {"formatVersion": 1, "game": "minecraft", "name": "Cozy", "dependencies": {"minecraft": "1.21.1", "fabric-loader": "0.16.9"},
         "files": [{"path": "mods/a.jar", "hashes": {}, "downloads": [], "fileSize": 100},
                   {"path": "mods/server.jar", "hashes": {}, "downloads": [], "fileSize": 50, "env": {"client": "unsupported", "server": "required"}}]}
        """
        let summary = try ModpackImport.inspect(zip(["modrinth.index.json": index, "overrides/config/a.toml": "x=1"], name: "cozy.mrpack"))
        XCTAssertEqual(summary.kind, .modrinth)
        XCTAssertEqual(summary.name, "Cozy")
        XCTAssertEqual(summary.gameVersion, "1.21.1")
        XCTAssertEqual(summary.loader, .fabric)
        XCTAssertEqual(summary.loaderVersion, "0.16.9")
        XCTAssertEqual(summary.downloads, 1)
        XCTAssertEqual(summary.downloadBytes, 100)
    }

    func testCurseForgePackInsideAFolderPicksNeoForgeNotForge() throws {
        let manifest = """
        {"name": "Big", "minecraft": {"version": "1.21.1", "modLoaders": [{"id": "neoforge-21.1.77", "primary": true}]},
         "files": [{"projectID": 1, "fileID": 2, "required": true}, {"projectID": 3, "fileID": 4, "required": false}]}
        """
        let summary = try ModpackImport.inspect(zip(["Big/manifest.json": manifest, "Big/overrides/config/b.toml": "y"]))
        XCTAssertEqual(summary.kind, .curseForge)
        XCTAssertEqual(summary.loader, .neoforge)
        XCTAssertEqual(summary.loaderVersion, "21.1.77")
        XCTAssertEqual(summary.downloads, 1)
    }

    func testOtherArchivesAreNamedNotImported() throws {
        XCTAssertEqual(try ModpackImport.inspect(zip(["mmc-pack.json": #"{"components": [{"uid": "net.minecraft", "version": "1.20.1"}]}"#])).kind, .multiMC)
        XCTAssertEqual(try ModpackImport.inspect(zip(["cofre.json": "{}", "mods/a.jar": "a"])).kind, .cofreInstance)
        XCTAssertEqual(try ModpackImport.inspect(zip(["mods/a.jar": "a", "config/a.toml": "b"])).kind, .plain)
        XCTAssertThrowsError(try ModpackImport.inspect(zip(["level.dat": "x", "db/CURRENT": "y"]))) { XCTAssertEqual($0 as? ModpackImport.Failure, .bedrockWorld) }
        XCTAssertThrowsError(try ModpackImport.inspect(zip(["World/level.dat": "x", "World/region/r.0.0.mca": "y"]))) { XCTAssertEqual($0 as? ModpackImport.Failure, .javaWorld) }
        XCTAssertThrowsError(try ModpackImport.inspect(zip(["fabric.mod.json": "{}"]))) { XCTAssertEqual($0 as? ModpackImport.Failure, .modFile) }
        XCTAssertThrowsError(try ModpackImport.inspect(zip(["readme.txt": "hi"]))) { XCTAssertEqual($0 as? ModpackImport.Failure, .unsupportedFormat) }
        XCTAssertThrowsError(try ModpackImport.inspect(zip(["modrinth.index.json": "{"]))) { XCTAssertEqual($0 as? ModpackImport.Failure, .invalidPack("The pack's modrinth.index.json is damaged.")) }
        let notZip = root.appendingPathComponent("half.mrpack")
        try Data("PK not really".utf8).write(to: notZip)
        XCTAssertThrowsError(try ModpackImport.inspect(notZip)) { XCTAssertEqual($0 as? ModpackImport.Failure, .notAZip) }
    }

    func testLinksResolveToPackFiles() throws {
        XCTAssertEqual(try ModpackImport.link(URL(string: "https://modrinth.com/modpack/fabulously-optimized")!), .modrinth(project: "fabulously-optimized", version: nil))
        XCTAssertEqual(try ModpackImport.link(URL(string: "https://modrinth.com/modpack/cozy/version/1.2.0")!), .modrinth(project: "cozy", version: "1.2.0"))
        let file = URL(string: "https://cdn.modrinth.com/data/abc/versions/def/Cozy.mrpack")!
        XCTAssertEqual(try ModpackImport.link(file), .file(file))
        XCTAssertThrowsError(try ModpackImport.link(URL(string: "https://www.curseforge.com/minecraft/modpacks/big")!)) { XCTAssertEqual($0 as? ModpackImport.Failure, .curseForgePage) }
        XCTAssertThrowsError(try ModpackImport.link(URL(string: "http://example.com/pack.mrpack")!))
        XCTAssertThrowsError(try ModpackImport.link(URL(string: "https://modrinth.com/mod/sodium")!))
        XCTAssertThrowsError(try ModpackImport.link(URL(string: "https://example.com/mod.jar")!))
    }

    func testPackFilePrefersTheRequestedVersionsMrpack() throws {
        let json = """
        [{"id": "new", "project_id": "p", "name": "2", "version_number": "2.0", "game_versions": [], "loaders": [], "version_type": "release", "dependencies": [],
          "files": [{"hashes": {}, "url": "https://cdn.modrinth.com/new.mrpack", "filename": "new.mrpack", "size": 1, "primary": true}]},
         {"id": "old", "project_id": "p", "name": "1", "version_number": "1.0", "game_versions": [], "loaders": [], "version_type": "release", "dependencies": [],
          "files": [{"hashes": {}, "url": "https://cdn.modrinth.com/readme.txt", "filename": "readme.txt", "size": 1, "primary": true},
                    {"hashes": {}, "url": "https://cdn.modrinth.com/old.mrpack", "filename": "old.mrpack", "size": 1, "primary": false}]}]
        """
        let versions = try JSONDecoder().decode([Modrinth.Version].self, from: Data(json.utf8))
        XCTAssertEqual(ModpackImport.packFile(in: versions, version: nil)?.filename, "new.mrpack")
        XCTAssertEqual(ModpackImport.packFile(in: versions, version: "1.0")?.filename, "old.mrpack")
        XCTAssertNil(ModpackImport.packFile(in: versions, version: "3.0"))
    }

    func testReceivedFilesAreStagedAndDiscarded() throws {
        let source = try zip(["mods/a.jar": "a"])
        let staged = try ModpackImport.receive(source, in: root)
        XCTAssertNotEqual(staged, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "a picked file stays where it was")
        XCTAssertEqual(try ModpackImport.inspect(staged).kind, .plain)
        ModpackImport.discard(staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
        ModpackImport.discard(source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "discard leaves files it didn't stage")

        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let shared = inbox.appendingPathComponent("shared.mrpack")
        try FileManager.default.copyItem(at: source, to: shared)
        let moved = try ModpackImport.receive(shared, in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path), "iOS's Inbox copy is moved, not kept")
        XCTAssertEqual(moved.lastPathComponent, "shared.mrpack")

        let leftover = try ModpackImport.stagingFile(named: "x.mrpack", in: root)
        try Data().write(to: leftover)
        ModpackImport.cleanupAbandonedStaging(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
    }
}
