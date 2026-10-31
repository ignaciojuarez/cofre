import CofreKit
import XCTest

final class PresetsTests: XCTestCase {
    func testBundledCatalogHasTheTwoMetalPresets() throws {
        XCTAssertEqual(
            Set(PresetCatalog.presets.map(\.id)), ["vanilla-plus-metal-26.3", "fabric-performance-metal-26.2"])
        try PresetCatalog.validate(.init(schema: 1, presets: PresetCatalog.presets))
        XCTAssertEqual(PresetCatalog.presets.first(where: { $0.loader == .vanilla })?.status, .recommended)
        let fabric = try XCTUnwrap(PresetCatalog.presets.first { $0.loader == .fabric })
        XCTAssertEqual(fabric.status, .experimental)
        XCTAssertEqual(fabric.pinnedMods.count, 8)
        XCTAssertTrue(fabric.pinnedMods.allSatisfy { $0.sha512.count == 128 })
        XCTAssertTrue(fabric.pinnedMods.allSatisfy { $0.project != "w79ASAJD" })
        XCTAssertEqual(fabric.optionalMods.first?.license, "AGPL-3.0-or-later")
        XCTAssertNotNil(fabric.metalRendererModPlaceholder)
    }

    func testPresetsHaveBothRAMTiersAndSelectByDeviceMemory() throws {
        for preset in PresetCatalog.presets {
            try preset.validate()
            XCTAssertNotEqual(preset.firstCreateOptions[.fourGB], preset.firstCreateOptions[.twelveGB])
            XCTAssertEqual(preset.options(forPhysicalMemoryMB: 4096).touchscreen, false)
            XCTAssertEqual(preset.options(forPhysicalMemoryMB: 12_000).menuBackgroundBlurriness, 0)
        }
    }

    func testValidationRejectsMissingHashesAndDuplicatePresetIDs() throws {
        let fabric = try XCTUnwrap(PresetCatalog.presets.first { $0.loader == .fabric })
        let first = try XCTUnwrap(fabric.pinnedMods.first)
        let badMod = CofrePreset.Mod(
            project: first.project, slug: first.slug, version: first.version, file: first.file, sha512: "",
            license: first.license)
        let bad = CofrePreset(
            id: fabric.id, name: fabric.name, pitch: fabric.pitch, gameVersion: fabric.gameVersion,
            loader: fabric.loader, loaderVersion: fabric.loaderVersion, renderer: fabric.renderer,
            status: fabric.status,
            pinnedMods: [badMod], firstCreateOptions: fabric.firstCreateOptions)
        XCTAssertThrowsError(try bad.validate())
        XCTAssertThrowsError(try PresetCatalog.validate(.init(schema: 1, presets: [fabric, fabric])))
    }
}
