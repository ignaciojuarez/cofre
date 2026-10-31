import XCTest

@testable import CofreKit

final class RendererPolicyTests: XCTestCase {
    func testExplicitAndGlobalChoicesOverrideAuto() {
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "mobileglues", globalSetting: "metallum", gameVersion: "26.3", loader: .fabric,
                metalVersions: ["26.3"]), "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", globalSetting: "mobileglues", gameVersion: "26.3", loader: .fabric,
                metalVersions: ["26.3"]), "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", globalSetting: "metallum", gameVersion: "26.3", loader: .fabric,
                metalVersions: ["26.3"]), "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                profile: ["lastVersionId": "26.3", "renderer": "metal"], metadata: ["id": "26.3"],
                globalSetting: "mobileglues", metalVersions: []), "libmetallum.dylib")
        XCTAssertEqual(
            RendererPolicy.resolve(
                profile: ["lastVersionId": "26.3"], metadata: ["id": "26.3"], globalSetting: "mobileglues",
                metalVersions: []), "libmobileglues.dylib")
    }

    func testCanonicalLoaderSurvivesResolvedBaseMinecraftMetadata() {
        let base: [String: Any] = ["id": "1.20.1", "libraries": [["name": "com.mojang:logging:1.1.1"]]]
        for loader in [Instance.Loader.forge, .neoforge] {
            XCTAssertEqual(
                RendererPolicy.resolve(
                    profile: ["lastVersionId": "1.20.1", "cofreRequestedLoader": loader.rawValue, "loader": "vanilla"],
                    metadata: base, globalSetting: "auto", metalVersions: []), "libmobileglues.dylib")
            XCTAssertEqual(
                RendererPolicy.resolve(
                    profile: ["lastVersionId": "1.20.1"], metadata: base, globalSetting: "auto", fallbackLoader: loader,
                    metalVersions: []), "libmobileglues.dylib")
        }
    }

    func testLegacyVersionIDAndNeoForgeLibrariesSelectMobileGlues() {
        XCTAssertEqual(
            RendererPolicy.resolve(
                profile: ["lastVersionId": "1.20.1-forge-47.1.106"], metadata: ["id": "1.20.1"], globalSetting: "auto",
                metalVersions: []), "libmobileglues.dylib")
        for artifact in ["net.neoforged:neoforge:21.1.77", "net.neoforged:forge:1.20.1-47.1.106"] {
            XCTAssertEqual(
                RendererPolicy.resolve(
                    profile: ["lastVersionId": "custom-install"],
                    metadata: ["id": "custom-install", "inheritsFrom": "1.20.1", "libraries": [["name": artifact]]],
                    globalSetting: "auto", metalVersions: []), "libmobileglues.dylib")
        }
    }

    func testAutoPickedRendererIsRecomputedForCurrentManifestAndGlobalChoice() {
        let profile: [String: Any] = [
            "lastVersionId": "26.3", "cofreRequestedLoader": "neoforge", "renderer": "libmetallum.dylib",
            "cofreRendererPicked": true,
        ]
        let metadata: [String: Any] = ["id": "26.3"]
        XCTAssertEqual(
            RendererPolicy.resolve(profile: profile, metadata: metadata, globalSetting: "auto", metalVersions: []),
            "libmobileglues.dylib")
        XCTAssertEqual(
            RendererPolicy.resolve(
                profile: profile, metadata: metadata, globalSetting: "auto", metalVersions: ["26.3"]),
            "libmobileglues.dylib")
        XCTAssertEqual(
            RendererPolicy.resolve(
                profile: profile, metadata: metadata, globalSetting: "mobileglues", metalVersions: ["26.3"]),
            "libmobileglues.dylib")
    }

    func testAutoMetalIsVanillaOnlyAndModdedVersionsUseMobileGlues() {
        let manifest: Set<String> = ["1.21.11", "26.2", "26.3"]
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "1.21.11", loader: .fabric, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.2", loader: .fabric, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.2", loader: .quilt, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.2", loader: .neoforge, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.2", loader: .vanilla, metalVersions: manifest),
            "metallum")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "1.21.11", loader: .vanilla, metalVersions: manifest),
            "metallum")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.4", loader: .fabric, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.4", loader: .forge, metalVersions: manifest),
            "mobileglues")
    }

    func testModRecommendationMatchesValidatedMetalRoutes() {
        let manifest: Set<String> = ["1.21.11", "26.2", "26.3"]
        XCTAssertTrue(
            RendererPolicy.isRecommendedForMods(gameVersion: "26.3", loader: .vanilla, metalVersions: manifest))
        XCTAssertFalse(
            RendererPolicy.isRecommendedForMods(gameVersion: "1.20.1", loader: .vanilla, metalVersions: manifest))
        XCTAssertTrue(RendererPolicy.isRecommendedForMods(gameVersion: "26.2", loader: .fabric, metalVersions: []))
        XCTAssertTrue(RendererPolicy.isRecommendedForMods(gameVersion: "1.21.11", loader: .fabric, metalVersions: []))
        XCTAssertTrue(RendererPolicy.isRecommendedForMods(gameVersion: "26.2", loader: .neoforge, metalVersions: []))
        XCTAssertFalse(
            RendererPolicy.isRecommendedForMods(gameVersion: "1.21.11", loader: .neoforge, metalVersions: manifest))
        XCTAssertFalse(
            RendererPolicy.isRecommendedForMods(gameVersion: "1.21.1", loader: .fabric, metalVersions: manifest))
        XCTAssertFalse(
            RendererPolicy.isRecommendedForMods(gameVersion: "26.2", loader: .forge, metalVersions: manifest))
        XCTAssertFalse(
            RendererPolicy.isRecommendedForMods(gameVersion: "26.2", loader: .quilt, metalVersions: manifest))
        XCTAssertEqual(RendererPolicy.detail(.mobileglues), "OpenGL translated on the CPU; slow for mods.")
    }

    func testSavedMetalFallsBackForModdedInstances() {
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "metallum", gameVersion: "26.2", loader: .fabric, metalVersions: ["26.2"]),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "libmetallum.dylib", gameVersion: "1.21.1", loader: .neoforge,
                metalVersions: ["1.21.1"]),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "metallum", gameVersion: "26.2", loader: .vanilla, metalVersions: ["26.2"]),
            "metallum")
    }

    func testDebugScenarioCanKeepExplicitMetallumForFabric() {
        #if DEBUG
            RendererPolicy.allowMetalForModdedScenario = true
            defer { RendererPolicy.allowMetalForModdedScenario = false }
            XCTAssertEqual(
                RendererPolicy.resolve(
                    setting: "metallum", gameVersion: "26.2", loader: .fabric,
                    metalVersions: ["26.2"]),
                "metallum")
            XCTAssertEqual(
                RendererPolicy.resolve(
                    setting: "metallum", gameVersion: "26.2", loader: .neoforge,
                    metalVersions: ["26.2"]),
                "metallum")
        #endif
    }

    func testAirIdentifiersUseAirLibraryNames() {
        let names: [(RendererID, String)] = [
            (.angle, "libtinygl4angle.dylib"),
            (.zink, "libOSMesa.8.dylib"),
            (.gl4es, "libgl4es_114.dylib"),
            (.simpleFPEWrapper, "libSimpleFPEWrapper.dylib"),
            (.mobileglues, "libmobileglues.dylib"),
            (.metallum, "libmetallum.dylib"),
            (.ltw, "libltw.dylib"),
            (.krypton, "libgl4eszl2.dylib"),
            ("mobilegl", "libMobileGL.dylib"),
            ("mobilegles", "libMobileGL-gles.dylib"),
            ("vulkan", "libMoltenVK.dylib"),
            ("vgpu", "libvgpu.dylib"),
            ("virgl", "libOSMesaVirgl.dylib"),
            ("nggl4es", "libnggl4es.dylib"),
        ]
        for (renderer, name) in names {
            XCTAssertEqual(RendererPolicy.airIdentifier(renderer).rawValue, name, renderer.rawValue)
        }
        XCTAssertEqual(RendererPolicy.airIdentifier("angle"), "libtinygl4angle.dylib")
        XCTAssertEqual(RendererPolicy.airIdentifier("libgl4es_114.dylib"), "libgl4es_114.dylib")
    }

    func testPickerHidesUnvalidatedRenderersButKeepsAHiddenSavedChoice() {
        let normal = RendererPolicy.pickerRenderers()
        XCTAssertEqual(
            normal.map(\.rawValue),
            ["auto", "metallum", "mobileglues", "zink", "gl4es", "simplefpewrapper", "angle"])
        XCTAssertFalse(normal.contains { RendererPolicy.sameRenderer($0, "ltw") })
        let saved = RendererPolicy.pickerRenderers(current: "libltw.dylib")
        XCTAssertTrue(saved.contains { RendererPolicy.sameRenderer($0, "libltw.dylib") })
        XCTAssertTrue(RendererPolicy.isHidden("libltw.dylib"))
    }

    func testPickerGatesLegacyAndMetalByInstance() {
        let manifest: Set<String> = ["1.21.11", "26.3"]
        let modern = RendererPolicy.pickerRenderers(
            gameVersion: "26.3", loader: .vanilla, metalVersions: manifest)
        XCTAssertEqual(modern.map(\.rawValue), ["auto", "metallum", "mobileglues"])
        XCTAssertFalse(modern.contains(.gl4es))
        XCTAssertFalse(modern.contains(.simpleFPEWrapper))
        let modded = RendererPolicy.pickerRenderers(
            gameVersion: "26.3", loader: .fabric, metalVersions: manifest)
        XCTAssertFalse(modded.contains(.metallum))
        XCTAssertTrue(modded.contains(.zink))
        let legacy = RendererPolicy.pickerRenderers(
            gameVersion: "1.16.5", loader: .vanilla, metalVersions: manifest)
        XCTAssertTrue(legacy.contains(.gl4es))
        XCTAssertTrue(legacy.contains(.simpleFPEWrapper))
    }

    func testRecommendedRendererFollowsAutoForVersionAndLoader() {
        let manifest: Set<String> = ["1.21.11", "26.3"]
        XCTAssertEqual(
            RendererPolicy.recommendedRenderer(gameVersion: "1.21.11", loader: .vanilla, metalVersions: manifest),
            .metallum)
        XCTAssertEqual(
            RendererPolicy.recommendedRenderer(gameVersion: "26.3", loader: .fabric, metalVersions: manifest),
            .mobileglues)
        XCTAssertEqual(
            RendererPolicy.recommendedRenderer(gameVersion: "1.16.5", loader: .vanilla, metalVersions: manifest),
            .gl4es)
    }

    func testFabricMetalNeedsMetalUniversalOnAValidatedVersion() {
        let manifest: Set<String> = ["26.2", "26.3"]
        // Auto, the global choice and a saved Metal pick all run Metal once the mod is in.
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", gameVersion: "26.2", loader: .fabric, metalVersions: manifest,
                metalMod: true), "metallum")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", gameVersion: "26.2", loader: .fabric, metalVersions: [],
                metalMod: true), "metallum")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "metallum", gameVersion: "26.2", loader: .fabric, metalVersions: manifest,
                metalMod: true), "metallum")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", globalSetting: "metallum", gameVersion: "26.2", loader: .fabric,
                metalVersions: manifest, metalMod: true), "metallum")
        // An explicit GL choice still wins.
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "mobileglues", gameVersion: "26.2", loader: .fabric,
                metalVersions: manifest, metalMod: true), "mobileglues")
        // Without the mod, or off its validated versions and loader, nothing changes.
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.2", loader: .fabric, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", gameVersion: "26.3", loader: .fabric, metalVersions: manifest,
                metalMod: true), "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "metallum", gameVersion: "26.2", loader: .neoforge,
                metalVersions: manifest), "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", gameVersion: "26.2", loader: .quilt, metalVersions: manifest,
                metalMod: true), "mobileglues")
    }

    func testFabricMetalPickerAndRecommendation() {
        let withMod = RendererPolicy.pickerRenderers(gameVersion: "26.2", loader: .fabric, metalMod: true)
        XCTAssertTrue(withMod.contains(.metallum))
        XCTAssertTrue(withMod.contains(.mobileglues))
        XCTAssertFalse(RendererPolicy.pickerRenderers(gameVersion: "26.2", loader: .fabric).contains(.metallum))
        XCTAssertEqual(
            RendererPolicy.recommendedRenderer(gameVersion: "26.2", loader: .fabric, metalVersions: [], metalMod: true),
            .metallum)
        XCTAssertEqual(
            RendererPolicy.recommendedRenderer(gameVersion: "26.2", loader: .fabric, metalVersions: []), .mobileglues)
    }

    func testNeoForgeMetalNeedsTheFourModKit() {
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", gameVersion: "26.2", loader: .neoforge, metalVersions: [], metalMod: true),
            .metallum)
        XCTAssertEqual(
            RendererPolicy.resolve(
                setting: "auto", gameVersion: "26.3", loader: .neoforge, metalVersions: [], metalMod: true),
            .mobileglues)
        XCTAssertTrue(
            RendererPolicy.pickerRenderers(gameVersion: "26.2", loader: .neoforge, metalMod: true).contains(.metallum))
        XCTAssertFalse(
            RendererPolicy.pickerRenderers(gameVersion: "26.2", loader: .neoforge).contains(.metallum))
    }

    func testLaunchHandsAirTheMetalLibraryForAFabricFolderWithMetalUniversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mods = root.appendingPathComponent("mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let profile: [String: Any] = ["lastVersionId": "fabric-loader-0.19.3-26.2", "cofreRequestedLoader": "fabric"]
        let metadata: [String: Any] = [
            "id": "fabric-loader-0.19.3-26.2", "inheritsFrom": "26.2",
            "libraries": [["name": "net.fabricmc:fabric-loader:0.19.3"]],
        ]
        func pick() -> RendererID {
            RendererPolicy.resolve(
                profile: profile, metadata: metadata, globalSetting: "auto", gameDirectory: root,
                metalVersions: ["26.2"])
        }
        XCTAssertEqual(pick(), "libmobileglues.dylib")
        // A jar named like Metal isn't enough: the Fabric id decides.
        try MetalModTests.jar(id: "notmetal").write(to: mods.appendingPathComponent("metallum-fake.jar"))
        XCTAssertEqual(pick(), "libmobileglues.dylib")
        try MetalModTests.jar(id: "metallum").write(to: mods.appendingPathComponent("metaluniversal.jar"))
        XCTAssertEqual(pick(), "libmetallum.dylib")
    }
}
