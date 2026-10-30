#if canImport(UIKit)
import XCTest
@testable import CofreUI

final class ModCompatibilityTests: XCTestCase {
    func testAutoUsesRendererForInstanceVersionAndLoader() {
        let fabric = InstanceSummary(id: "f", name: "Fabric", loader: .fabric, gameVersion: "1.21.1")
        XCTAssertEqual(ModCompatibility.renderer(globalSetting: "auto", gameVersion: "1.21.1", loader: "fabric"), "air")
        XCTAssertEqual(ModCompatibility.renderer(globalSetting: "auto", gameVersion: "1.21.1", loader: "forge"), "mobileglues")
        // Versions the bundled Metallum supports run Metal on Auto, Forge and NeoForge too (as the launch decides).
        ModCompatibility.metalVersions = ["26.2"]
        defer { ModCompatibility.metalVersions = [] }
        XCTAssertEqual(ModCompatibility.renderer(globalSetting: "auto", gameVersion: "26.2", loader: "neoforge"), "metallum")
        // Air loads Metallum only for 26+, so 1.21.11 stays on the GL path.
        XCTAssertEqual(ModCompatibility.renderer(globalSetting: "auto", gameVersion: "1.21.11", loader: "fabric"), "air")
    }
    func testVerifiedIrisAndSodiumOnlyWorkOnMetal261211And262() {
        XCTAssertNil(ModCompatibility.entry(for: "iris")?.issue(gameVersion: "26.2", renderer: "metallum"))
        XCTAssertNotNil(ModCompatibility.entry(for: "iris")?.issue(gameVersion: "26.3", renderer: "metallum"))
        XCTAssertNil(ModCompatibility.entry(for: "sodium")?.issue(gameVersion: "1.21.11", renderer: "metallum"))
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
