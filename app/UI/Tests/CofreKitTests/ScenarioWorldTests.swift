import XCTest

@testable import CofreKit

final class ScenarioWorldTests: XCTestCase {
    func testWritesReadableWorldFixtureForBothScenarioVersions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for version in ["26.2", "1.21.11"] {
            let world = root.appendingPathComponent(version)
            try ScenarioWorld.write(to: world, folder: "Bench", seed: 1234, gameVersion: version)
            let level = try NBT.read(Data(contentsOf: world.appendingPathComponent("level.dat")))
            XCTAssertEqual(level["Data"]?["DataVersion"]?.integer, version == "26.2" ? 4903 : 4671)
            XCTAssertEqual(level["Data"]?["RandomSeed"]?.integer, 1234)
            XCTAssertEqual(level["Data"]?["Version"]?["Name"]?.string, version)
            if version == "26.2" {
                let settings = try NBT.read(
                    Data(contentsOf: world.appendingPathComponent("data/minecraft/world_gen_settings.dat")))
                XCTAssertEqual(settings["data"]?["seed"]?.integer, 1234)
                XCTAssertNil(level["Data"]?["WorldGenSettings"])
            } else {
                XCTAssertEqual(level["Data"]?["WorldGenSettings"]?["seed"]?.integer, 1234)
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: world.appendingPathComponent("data/minecraft/world_gen_settings.dat").path))
            }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: world.appendingPathComponent("saves", isDirectory: true).path)
                    == false)
        }
    }

    func testEnsureCreatesSavesFolderAndPreservesExistingWorld() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ScenarioWorld.ensure(in: root, folder: "Bench", seed: 1, gameVersion: "26.2")
        let before = try Data(contentsOf: first.appendingPathComponent("level.dat"))
        _ = try ScenarioWorld.ensure(in: root, folder: "Bench", seed: 2, gameVersion: "26.2")
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("level.dat")), before)
    }
}
