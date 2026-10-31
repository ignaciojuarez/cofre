import XCTest

@testable import CofreKit

final class ContentCompatibilityTests: XCTestCase {
    private let manifest = RendererManifest(
        gameVersions: ["1.21.11", "26.2", "26.3"],
        integrations: ["iris": ["26.2"], "sodium": ["1.21.11", "26.2"], "mixin": ["26.2"]])
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for dir in ["mods", "shaderpacks", "config"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func write(_ path: String, _ text: String = "") throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    private func issue(_ name: String, _ kind: ContentKind = .mods, _ game: String, _ renderer: String)
        -> CompatibilityIssue?
    {
        ContentCompatibility.issue(
            id: name, name: name, kind: kind, gameVersion: game, renderer: renderer, manifest: manifest)
    }

    func testMetalFlagsModsEvenOnManifestVersions() throws {
        let iris = try XCTUnwrap(issue("iris-fabric-1.8.0+mc26.3", .mods, "26.3", "metallum"))
        XCTAssertEqual(iris.badge, "Not on Metal · 26.3")
        XCTAssertEqual(iris.title, "Iris doesn't run here")
        XCTAssertEqual(iris.reason, "Iris needs OpenGL; Metal runs without shaders for now.")
        XCTAssertNotNil(issue("Iris Shaders", .mods, "26.2", "metallum"))
        XCTAssertEqual(
            issue("Sodium", .mods, "1.21.11", "libmetallum.dylib")?.reason,
            "Metal runs this mod only on Fabric 26.2 for now.")
        // MetalUniversal on Fabric 26.2 renders with Sodium (iPad mini, 57 FPS in world).
        XCTAssertNil(issue("sodium-fabric-0.9.0+mc26.2", .mods, "26.2", "libmetallum.dylib"))
        XCTAssertNil(issue("metallum-1.0.4", .mods, "26.2", "libmetallum.dylib"))
        // Metallum's own mixin package isn't a mod; an unknown mod has no evidence either way.
        XCTAssertNil(issue("MixinExtras", .mods, "26.3", "metallum"))
        XCTAssertNil(issue("JEI", .mods, "26.3", "metallum"))
        // Off Metal the manifest says nothing about mods.
        XCTAssertNil(issue("Sodium", .mods, "26.3", "mobileglues"))
        XCTAssertNil(issue("Iris", .mods, "1.21.1", "mobileglues"))
    }

    func testIrisOn26xGLPathsIsFlaggedAsBlackScreen() throws {
        let mg = try XCTUnwrap(issue("iris-fabric-1.10.0+mc26.2", .mods, "26.2", "libmobileglues.dylib"))
        XCTAssertEqual(mg.title, "Iris doesn't run here")
        XCTAssertEqual(mg.badge, "Not on MobileGlues · 26.2")
        XCTAssertNotNil(issue("Iris Shaders", .mods, "26.3", "libtinygl4angle.dylib"))
        XCTAssertNil(issue("Iris", .mods, "26.2", "zink"))
    }

    func testShaderPacksWarnOnMobileGluesAndOnMetalWithoutIris() throws {
        let mg = try XCTUnwrap(issue("Complementary", .shaders, "1.21.1", "mobileglues"))
        XCTAssertEqual(mg.badge, "Not on MobileGlues · 1.21.1")
        XCTAssertEqual(mg.title, "Shaders don't run here")
        XCTAssertNotNil(issue("BSL", .shaders, "26.3", "metallum"))
        XCTAssertEqual(
            issue("BSL", .shaders, "26.2", "metallum")?.reason, "Iris needs OpenGL; Metal runs without shaders for now."
        )
        XCTAssertNil(issue("BSL", .shaders, "1.21.1", "air"))
        XCTAssertNil(issue("Faithful", .resourcePacks, "26.3", "metallum"))
        // Shader packs are not a Metal path even without a manifest.
        XCTAssertNotNil(
            ContentCompatibility.issue(
                id: "BSL", name: "BSL", kind: .shaders, gameVersion: "26.3",
                renderer: "metallum", manifest: RendererManifest()))
    }

    func testPlayCheckCoversEnabledModsAndTheActiveShaderPack() throws {
        try write("mods/iris-neoforge-1.8.14+mc1.21.1.jar")
        try write("mods/sodium-old.jar.disabled")
        try write("shaderpacks/ComplementaryReimagined_r5.9.3.zip")
        try write("config/iris.properties", "enableShaders=true\nshaderPack=ComplementaryReimagined_r5.9.3.zip\n")
        // MobileGlues: Iris itself loads, the pack doesn't.
        let mg = ContentCompatibility.playIssues(
            gameDirectory: root, gameVersion: "1.21.1", renderer: "mobileglues", manifest: manifest)
        XCTAssertEqual(mg.map(\.kind), [.shaders])
        XCTAssertEqual(mg.first?.file, "ComplementaryReimagined_r5.9.3.zip")
        // Turn off and play: the game's own switch goes off, so the next check is clean.
        try ContentCompatibility.turnOff(mg, gameDirectory: root)
        XCTAssertFalse(ShaderSwitch.isOn(in: root))
        XCTAssertTrue(
            ContentCompatibility.playIssues(
                gameDirectory: root, gameVersion: "1.21.1", renderer: "mobileglues", manifest: manifest
            ).isEmpty)
    }

    func testPlayCheckOnMetalTurnsOffTheModAndSkipsItsPack() throws {
        try write("mods/iris-fabric-1.8.0+mc26.3.jar")
        try write("shaderpacks/BSL.zip")
        try write("config/iris.properties", "enableShaders=true\nshaderPack=BSL.zip\n")
        let issues = ContentCompatibility.playIssues(
            gameDirectory: root, gameVersion: "26.3", renderer: "metallum", manifest: manifest)
        XCTAssertEqual(issues.map(\.modName), ["Iris"])
        try ContentCompatibility.turnOff(issues, gameDirectory: root)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("mods/iris-fabric-1.8.0+mc26.3.jar.disabled").path))
        // Without an enabled shader mod, a configured pack doesn't run, so there's nothing to flag.
        XCTAssertTrue(
            ContentCompatibility.playIssues(
                gameDirectory: root, gameVersion: "26.3", renderer: "metallum", manifest: manifest
            ).isEmpty)
    }

    func testPlayCheckOnFabricMetalKeepsSodiumAndFlagsIris() throws {
        try write("mods/metallum-1.0.4.jar")
        try write("mods/sodium-fabric-0.9.0+mc26.2.jar")
        try write("mods/iris-fabric-1.10.0+mc26.2.jar")
        let issues = ContentCompatibility.playIssues(
            gameDirectory: root, gameVersion: "26.2", renderer: "libmetallum.dylib", manifest: manifest)
        XCTAssertEqual(issues.map(\.modName), ["Iris"])
        XCTAssertEqual(issues.first?.file, "iris-fabric-1.10.0+mc26.2.jar")
    }
}
