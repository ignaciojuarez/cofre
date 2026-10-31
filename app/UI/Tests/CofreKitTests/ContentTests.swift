import XCTest
@testable import CofreKit

final class ContentTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for dir in ["mods", "resourcepacks", "shaderpacks", "config", "saves/world/datapacks", "saves/other/datapacks"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func write(_ path: String, _ text: String = "") throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func testListToggleDeleteUndoAndInUse() throws {
        try write("mods/jei-19.1.jar"); try write("mods/old.jar.disabled")
        try write("resourcepacks/Faithful-32.zip"); try write("resourcepacks/Other.zip"); try write("shaderpacks/BSL.zip")
        try write("saves/world/datapacks/test.zip")
        try write("options.txt", "resourcePacks:[\"vanilla\",\"file/Faithful-32.zip\"]\n")
        try write("config/iris.properties", "enableShaders=true\nshaderPack=BSL.zip\n")
        let store = ContentStore(gameDirectory: root)
        let mods = try store.list(.mods); XCTAssertEqual(mods.count, 2); XCTAssertFalse(mods.first { $0.id == "old.jar" }!.enabled)
        let packs = try store.list(.resourcePacks)
        XCTAssertEqual(packs.filter(\.inUse).map(\.id), ["Faithful-32.zip"])
        XCTAssertTrue(try store.list(.shaders).first!.inUse)
        let mod = try XCTUnwrap(mods.first { $0.enabled }); try store.setEnabled(false, mod); XCTAssertFalse(try store.list(.mods).first { $0.id == mod.id }!.enabled)
        let pack = packs[0]
        let token = try store.trash(pack); XCTAssertEqual(try store.list(.resourcePacks).count, 1); try store.restore(token); XCTAssertEqual(try store.list(.resourcePacks).count, 2)
        XCTAssertEqual(try store.list(.dataPacks).first?.world, "world")
    }

    func testModpacksAreRejectedAndKindsKeepFolderNames() throws {
        XCTAssertThrowsError(try ContentStore(gameDirectory: root).list(.modpacks))
        XCTAssertEqual(ContentKind.allCases.map(\.folderName), ["mods", "shaderpacks", "resourcepacks", "datapacks", nil])
        XCTAssertEqual(ContentKind.allCases.filter(\.isInstallable), [.mods, .shaders, .resourcePacks])
        // Raw values are saved (filters, plans), so they never change.
        XCTAssertEqual(ContentKind.allCases.map(\.rawValue), ["mods", "shaders", "resourcePacks", "dataPacks", "modpacks"])
    }

    func testSamePackInTwoWorldsStaysTwoItemsAndTogglesItsOwnFile() throws {
        try write("saves/world/datapacks/pack.zip"); try write("saves/other/datapacks/pack.zip")
        let store = ContentStore(gameDirectory: root)
        let items = try store.list(.dataPacks)
        XCTAssertEqual(Set(items.map(\.id)), ["world/pack.zip", "other/pack.zip"])
        try store.setEnabled(false, try XCTUnwrap(items.first { $0.world == "other" }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("saves/other/datapacks/pack.zip.disabled").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("saves/world/datapacks/pack.zip").path))
        let off = try XCTUnwrap(try store.list(.dataPacks).first { !$0.enabled })
        XCTAssertEqual(store.url(of: off).lastPathComponent, "pack.zip.disabled")
    }

    func testShaderInUseFollowsTheShaderModSwitch() throws {
        try write("shaderpacks/Complementary Reimagined.zip")
        let store = ContentStore(gameDirectory: root)
        try write("config/oculus.properties", "shaderPack=Complementary Reimagined.zip\nenableShaders=false\n")
        XCTAssertNil(store.activeShaderPack())
        try write("config/oculus.properties", "shaderPack=Complementary Reimagined.zip\nenableShaders=true\n")
        XCTAssertEqual(store.activeShaderPack(), "Complementary Reimagined.zip")
        XCTAssertTrue(try store.list(.shaders)[0].inUse)
        try FileManager.default.removeItem(at: root.appendingPathComponent("config/oculus.properties"))
        try write("optionsshaders.txt", "shaderPack=OFF\n")
        XCTAssertNil(store.activeShaderPack())
        XCTAssertEqual(ContentStore.properties("shaderPack=My\\ Pack\\:1.zip\n# x=y\n"), ["shaderPack": "My Pack:1.zip"])
    }

    func testUpdateLoadersPerKind() {
        XCTAssertEqual(ContentKind.mods.updateLoaders(.quilt), ["quilt", "fabric"])
        XCTAssertEqual(ContentKind.resourcePacks.updateLoaders(.fabric), ["minecraft"])
        XCTAssertTrue(ContentKind.shaders.updateLoaders(.neoforge).contains("iris"))
    }
}
