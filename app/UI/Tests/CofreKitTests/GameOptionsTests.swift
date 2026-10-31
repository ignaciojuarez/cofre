import CofreKit
import XCTest

final class GameOptionsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var file: URL { dir.appendingPathComponent("options.txt") }
    private func options() throws -> String { try String(contentsOf: file, encoding: .utf8) }
    private func write(_ text: String) throws { try text.write(to: file, atomically: true, encoding: .utf8) }

    func testNewInstanceGetsPlayableDistances() throws {
        XCTAssertTrue(try GameOptions.seedDistances(in: dir, physicalMB: 12000, replacingEngineDefaults: true))
        XCTAssertEqual(try options(), "renderDistance:10\nsimulationDistance:8")
    }

    func testSmallDevicesGetShorterDistances() throws {
        try write("lang:en_us\n")
        try GameOptions.seedDistances(in: dir, physicalMB: 3862, replacingEngineDefaults: false)
        XCTAssertEqual(try options(), "lang:en_us\nrenderDistance:6\nsimulationDistance:5\n")
    }

    func testEngineDefaultsAreReplacedOnlyWhenAsked() throws {
        try write("renderDistance:2\nsimulationDistance:5")
        XCTAssertFalse(try GameOptions.seedDistances(in: dir, physicalMB: 12000, replacingEngineDefaults: false))
        XCTAssertTrue(try GameOptions.seedDistances(in: dir, physicalMB: 12000, replacingEngineDefaults: true))
        XCTAssertEqual(try options(), "renderDistance:10\nsimulationDistance:8")
    }

    func testPlayerChoiceIsKept() throws {
        try write("renderDistance:16\nsimulationDistance:12")
        XCTAssertFalse(try GameOptions.seedDistances(in: dir, physicalMB: 12000, replacingEngineDefaults: true))
        XCTAssertEqual(try options(), "renderDistance:16\nsimulationDistance:12")
    }

    func testPresetSeedsSettingsWithoutReplacingExistingOptions() throws {
        let preset = try XCTUnwrap(PresetCatalog.presets.first)
        XCTAssertTrue(try GameOptions.seedPreset(preset.options(forPhysicalMemoryMB: 3862), in: dir, physicalMB: 3862))
        let first = try options()
        XCTAssertTrue(first.contains("renderDistance:6"))
        XCTAssertTrue(first.contains("simulationDistance:5"))
        XCTAssertTrue(first.contains("menuBackgroundBlurriness:0"))
        XCTAssertTrue(first.contains("touchscreen:false"))
        XCTAssertTrue(first.contains("maxFps:60"))

        try write("renderDistance:16\nmaxFps:30\n")
        XCTAssertTrue(
            try GameOptions.seedPreset(preset.options(forPhysicalMemoryMB: 12000), in: dir, physicalMB: 12000))
        let preserved = try options()
        XCTAssertTrue(preserved.contains("renderDistance:16"))
        XCTAssertTrue(preserved.contains("maxFps:30"))
        XCTAssertFalse(preserved.contains("renderDistance:10"))
    }
}
