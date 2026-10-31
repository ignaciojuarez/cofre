import CofreKit
import XCTest

final class PresetsTests: XCTestCase {
    func testBundledCatalogHasTheThreeMetalPresets() throws {
        XCTAssertEqual(
            Set(PresetCatalog.presets.map(\.id)),
            ["vanilla-plus-metal-26.3", "fabric-performance-metal-26.2", "neoforge-metal-26.2"])
        try PresetCatalog.validate(.init(schema: 1, presets: PresetCatalog.presets))
        XCTAssertEqual(PresetCatalog.presets.first(where: { $0.loader == .vanilla })?.status, .recommended)
        let fabric = try XCTUnwrap(PresetCatalog.presets.first { $0.loader == .fabric })
        XCTAssertEqual(fabric.status, .experimental)
        XCTAssertEqual(fabric.pinnedMods.count, 9)
        XCTAssertTrue(fabric.pinnedMods.allSatisfy { $0.sha512.count == 128 })
        XCTAssertTrue(fabric.pinnedMods.allSatisfy { $0.project != "w79ASAJD" })
        XCTAssertEqual(fabric.optionalMods.first?.license, "AGPL-3.0-or-later")
        // The Metal path: the stock MetalUniversal jar and the Sodium build it rendered with on the iPad.
        XCTAssertEqual(fabric.pinnedMods.filter { $0.url != nil }, [MetalMod.pin])
        let sodium = try XCTUnwrap(fabric.pinnedMods.first { $0.slug == "sodium" })
        XCTAssertEqual(sodium.version, "3QgJXuSK")
        XCTAssertEqual(sodium.file, "sodium-fabric-0.9.0+mc26.2.jar")
        XCTAssertTrue(MetalMod.supports(gameVersion: fabric.gameVersion, loader: fabric.loader))
        let neo = try XCTUnwrap(PresetCatalog.presets.first { $0.loader == .neoforge })
        XCTAssertEqual(neo.status, .experimental)
        XCTAssertEqual(neo.loaderVersion, "26.2.0.93")
        XCTAssertEqual(neo.pinnedMods.count, 9)
        XCTAssertEqual(neo.pinnedMods.filter { $0.url != nil }, [MetalMod.pin])
        XCTAssertEqual(
            Set(neo.pinnedMods.map(\.slug)),
            [
                "metaluniversal", "connector", "forgified-fabric-api", "launchpad", "ferrite-core",
                "lithium", "mouse-tweaks", "controlify", "jei",
            ])
        XCTAssertEqual(neo.options(forPhysicalMemoryMB: 4096).renderDistance, 5)
        XCTAssertEqual(neo.options(forPhysicalMemoryMB: 4096).simulationDistance, 4)
        XCTAssertTrue(MetalMod.supports(gameVersion: neo.gameVersion, loader: neo.loader))
    }

    func testURLPinsDecodeAndMustBeHTTPS() throws {
        let json = #"""
            {"project": "EternityQwQ/MetalUniversal", "slug": "metaluniversal", "version": "1.0.4",
             "file": "metallum-1.0.4.jar", "sha512": "\#(MetalMod.pin.sha512)", "license": "MIT",
             "url": "\#(MetalMod.pin.url!)"}
            """#
        let mod = try JSONDecoder().decode(CofrePreset.Mod.self, from: Data(json.utf8))
        XCTAssertEqual(mod, MetalMod.pin)
        let modrinth = try JSONDecoder().decode(
            CofrePreset.Mod.self,
            from: JSONEncoder().encode(PresetCatalog.presets.flatMap(\.pinnedMods).first { $0.slug == "lithium" }))
        XCTAssertNil(modrinth.url)
        let fabric = try XCTUnwrap(PresetCatalog.presets.first { $0.loader == .fabric })
        let plain = CofrePreset.Mod(
            project: mod.project, slug: mod.slug, version: mod.version, file: mod.file, sha512: mod.sha512,
            license: mod.license, url: "http://example.com/metallum.jar")
        let bad = CofrePreset(
            id: fabric.id, name: fabric.name, pitch: fabric.pitch, gameVersion: fabric.gameVersion,
            loader: fabric.loader, loaderVersion: fabric.loaderVersion, renderer: fabric.renderer,
            status: fabric.status, pinnedMods: [plain], firstCreateOptions: fabric.firstCreateOptions)
        XCTAssertThrowsError(try bad.validate())
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
