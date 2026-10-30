import XCTest
import CofreKit
@testable import CofreUI

final class EffectiveRendererTests: XCTestCase {
    func testProfilesPreserveOverridesButReResolveAutoPicks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let profiles: [String: Any] = ["profiles": [
            "explicit": ["name": "Explicit", "lastVersionId": "1.21.1", "renderer": "libmetallum.dylib"],
            "picked": ["name": "Picked", "lastVersionId": "1.21.1", "renderer": "libmetallum.dylib", "cofreRendererPicked": true],
        ]]
        try JSONSerialization.data(withJSONObject: profiles).write(to: root.appendingPathComponent("launcher_profiles.json"))
        let instances = try InstanceStore(root: root).list()
        XCTAssertEqual(instances.first { $0.id == "explicit" }?.renderer, "libmetallum.dylib")
        XCTAssertEqual(instances.first { $0.id == "picked" }?.renderer, "auto")
    }

    func testWarningsFollowEffectiveRenderer() {
        let saved = ModCompatibility.metalVersions
        ModCompatibility.metalVersions = ["26.3"]
        defer { ModCompatibility.metalVersions = saved }
        let iris = ModCompatibility(id: "iris", name: "Iris", metalVersions: [], reason: "No integration", verified: true)
        func issue(_ own: String, _ global: String, _ game: String) -> ModCompatibilityIssue? {
            iris.issue(gameVersion: game, renderer: ModCompatibility.renderer(instanceSetting: own, globalSetting: global, gameVersion: game, loader: "fabric"))
        }
        XCTAssertNil(issue("auto", "auto", "1.21.1"))
        XCTAssertNotNil(issue("metallum", "auto", "1.21.1"))
        XCTAssertNil(issue("angle", "metallum", "26.3"))
        XCTAssertNotNil(issue("auto", "auto", "26.3"))
        XCTAssertNotNil(issue("auto", "metallum", "1.21.1"))
        XCTAssertEqual(ModCompatibility.renderer(instanceSetting: "auto", globalSetting: "auto", gameVersion: "1.21.1", loader: "neoforge"), "mobileglues")
        XCTAssertEqual(ModCompatibility.renderer(globalSetting: "auto", gameVersion: "26.3", loader: "fabric", javaVersion: 17), "air")
    }
}
