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
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.4", loader: .fabric, metalVersions: manifest),
            "mobileglues")
        XCTAssertEqual(
            RendererPolicy.resolve(setting: "auto", gameVersion: "26.4", loader: .forge, metalVersions: manifest),
            "mobileglues")
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
        #endif
    }
}
