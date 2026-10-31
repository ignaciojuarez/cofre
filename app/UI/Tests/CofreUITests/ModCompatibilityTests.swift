#if canImport(UIKit)
import XCTest
@testable import CofreUI
import CofreKit

final class ModCompatibilityTests: XCTestCase {
    override func setUp() {
        ModCompatibility.manifest = RendererManifest(integrations: ["iris": ["26.2"], "sodium": ["1.21.11", "26.2"]])
    }
    override func tearDown() { ModCompatibility.manifest = RendererManifest() }
    func testAutoUsesRendererForInstanceVersionAndLoader() {
        XCTAssertEqual(ModCompatibility.renderer(setting: "auto", gameVersion: "1.21.1", loader: "fabric"), "mobileglues")
        XCTAssertEqual(ModCompatibility.renderer(setting: "auto", gameVersion: "1.21.1", loader: "forge"), "mobileglues")
        // A loader always uses the GL renderer, even when the base version is in Metallum's manifest.
        ModCompatibility.metalVersions = ["26.2"]
        defer { ModCompatibility.metalVersions = [] }
        XCTAssertEqual(ModCompatibility.renderer(globalSetting: "auto", gameVersion: "26.2", loader: "neoforge"), "mobileglues")
        // Air loads Metallum only for vanilla 26+, so 1.21.11 stays on the GL path.
        XCTAssertEqual(ModCompatibility.renderer(setting: "auto", gameVersion: "1.21.11", loader: "fabric"), "mobileglues")
    }
    func testModsDoNotOfferMetalEvenOnManifestVersions() {
        XCTAssertEqual(
            ModCompatibility.entry(for: "iris")?.issue(gameVersion: "26.2", renderer: "metallum")?.reason,
            "Iris needs OpenGL; Metal runs without shaders for now.")
        XCTAssertNotNil(ModCompatibility.entry(for: "iris")?.issue(gameVersion: "26.3", renderer: "metallum"))
        XCTAssertEqual(
            ModCompatibility.entry(for: "sodium")?.issue(gameVersion: "1.21.11", renderer: "metallum")?.reason,
            "Metal runs this mod only on Fabric 26.2 for now.")
    }

    func testLaunchDecisionWarnsOnlyEnabledIncompatibleMods() {
        let items = [
            InstalledItem(id: "iris.jar", name: "Iris", version: "1", enabled: true, projectID: "iris"),
            InstalledItem(id: "sodium.jar", name: "Sodium", version: "1", enabled: false, projectID: "sodium"),
        ]
        guard case .warn(let issues) = ModCompatibilityChecker.decision(items: items, gameVersion: "26.3", renderer: "metallum") else {
            return XCTFail("expected warning")
        }
        XCTAssertEqual(issues.map(\.modName), ["Iris"])
    }
}
#endif
