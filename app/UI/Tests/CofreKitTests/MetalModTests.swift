import XCTest

@testable import CofreKit

final class MetalModTests: XCTestCase {
    /// A minimal Fabric jar with just its `fabric.mod.json`.
    static func jar(id: String) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jar")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = Data(#"{"schemaVersion":1,"id":"\#(id)","version":"1.0.4"}"#.utf8)
        try Zip.write([(path: "fabric.mod.json", data: { json })], to: url)
        return try Data(contentsOf: url)
    }

    func testDetectsTheEnabledJarByItsFabricID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mods = root.appendingPathComponent("mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        XCTAssertFalse(MetalMod.isEnabled(in: root))
        try Self.jar(id: "sodium").write(to: mods.appendingPathComponent("sodium.jar"))
        try Data("not a zip".utf8).write(to: mods.appendingPathComponent("broken.jar"))
        XCTAssertFalse(MetalMod.isEnabled(in: root))
        // Turned off in Mods: Fabric won't load it, so it doesn't count.
        try Self.jar(id: "metallum").write(to: mods.appendingPathComponent("metallum-1.0.4.jar.disabled"))
        XCTAssertFalse(MetalMod.isEnabled(in: root))
        try FileManager.default.moveItem(
            at: mods.appendingPathComponent("metallum-1.0.4.jar.disabled"),
            to: mods.appendingPathComponent("metallum-1.0.4.jar"))
        XCTAssertTrue(MetalMod.isEnabled(in: root))
    }

    func testOnlyFabricOnValidatedVersions() {
        XCTAssertTrue(MetalMod.supports(gameVersion: "26.2", loader: .fabric))
        XCTAssertFalse(MetalMod.supports(gameVersion: "26.3", loader: .fabric))
        XCTAssertFalse(MetalMod.supports(gameVersion: "26.2", loader: .quilt))
        XCTAssertFalse(MetalMod.supports(gameVersion: "26.2", loader: .vanilla))
    }

    func testPinIsTheDeviceValidatedJar() {
        XCTAssertEqual(MetalMod.pin.file, "metallum-1.0.4.jar")
        XCTAssertEqual(MetalMod.pin.sha512.count, 128)
        XCTAssertEqual(
            MetalMod.pin.url,
            "https://github.com/EternityQwQ/MetalUniversal/releases/download/MetalUniversal_1.0.4/metallum-1.0.4.jar")
    }
}
