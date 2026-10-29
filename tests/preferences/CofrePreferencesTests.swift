import XCTest
import CofreCore
import CofreUI

final class CofrePreferencesTests: XCTestCase {
    func testDefaultsAndKeyMapping() {
        let store = MemoryStore()
        let preferences = store.owner.load(instanceID: nil)
        XCTAssertTrue(store.readKeys.contains(CofrePreferenceStore.Key.renderer.rawValue))
        XCTAssertTrue(store.readKeys.contains(CofrePreferenceStore.Key.computeShaders.rawValue))
        XCTAssertEqual(preferences.shaderCacheMB, 128)
        XCTAssertEqual(preferences.computeShaders, false)
        XCTAssertEqual(preferences.fsrMode, .off)
    }

    func testProfileOverridesGlobal() {
        let store = MemoryStore()
        store.values["video.renderer|global"] = "libmobileglues.dylib"
        store.values["video.renderer|instance"] = "libmetallum.dylib"
        XCTAssertEqual(store.owner.load(instanceID: "instance").renderer, "libmetallum.dylib")
        XCTAssertEqual(store.owner.load(instanceID: nil).renderer, "libmobileglues.dylib")
    }

    func testRoundTripUsesTypedValues() {
        let store = MemoryStore()
        var preferences = GamePreferences()
        preferences.renderer = "libmetallum.dylib"
        preferences.graphicsApi = "vulkan"
        preferences.resolution = 0.75
        preferences.computeShaders = true
        preferences.envVariables = ["JAVA_TOOL_OPTIONS": "-Xmx2G"]
        store.owner.save(preferences, instanceID: "instance")
        let loaded = store.owner.load(instanceID: "instance")
        XCTAssertEqual(loaded.renderer, preferences.renderer)
        XCTAssertEqual(loaded.graphicsApi, preferences.graphicsApi)
        XCTAssertEqual(loaded.resolution, preferences.resolution)
        XCTAssertEqual(loaded.computeShaders, preferences.computeShaders)
        XCTAssertEqual(loaded.envVariables, preferences.envVariables)
    }

    private final class MemoryStore {
        var values: [String: Any] = [:]
        var readKeys: [String] = []
        lazy var owner = CofrePreferenceStore(
            read: { [weak self] key, profile in
                self?.readKeys.append(key)
                return self?.values["\(key)|\(profile ?? "global")"]
            },
            write: { [weak self] key, value, profile in
                self?.values["\(key)|\(profile ?? "global")"] = value
            })
    }
}
