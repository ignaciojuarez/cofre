import XCTest
@testable import CofreKit

final class ScenarioTests: XCTestCase {
    func testDefaultsAndValidation() throws {
        let s = try CofreScenario.load(Data(#"{"name":"fab","version":"1.21.1","loader":"fabric","mods":["sodium"]}"#.utf8))
        XCTAssertEqual(s.renderer, "auto"); XCTAssertTrue(s.launch)
    }

    func testWorldAndSeedDecodeAndValidate() throws {
        let s = try CofreScenario.load(Data(#"{"name":"bench","version":"26.2","world":"Bench","seed":1234}"#.utf8))
        XCTAssertEqual(s.world, "Bench"); XCTAssertEqual(s.seed, 1234)
        XCTAssertThrowsError(try CofreScenario(name: "bench", version: "26.2", seed: 1).validate())
        XCTAssertThrowsError(try CofreScenario(name: "bench", version: "26.2", world: "../escape").validate())
    }

    func testEngineExperimentsDecode() throws {
        let s = try CofreScenario.load(Data(#"{"name":"ab","version":"26.3","engine":{"codeCacheMB":256,"detachJIT":true}}"#.utf8))
        XCTAssertEqual(s.engine, EngineOptions(codeCacheMB: 256, detachJIT: true))
        XCTAssertNil(try CofreScenario.load(Data(#"{"name":"ab","version":"26.3"}"#.utf8)).engine)
    }

    func testRejectsPackWithModsAndBadResolution() {
        let s = CofreScenario(name: "x", version: "1.21.1", mods: ["sodium"], pack: "pack", resolution: 2)
        XCTAssertThrowsError(try s.validate())
    }

    func testRemoteFilesDecodeAndRejectTraversal() throws {
        let s = try CofreScenario.load(Data(#"{"name":"metal","version":"26.2","loader":"fabric","files":[{"url":"https://example.com/metallum.jar","to":"mods/metallum.jar"}]}"#.utf8))
        XCTAssertEqual(s.files.first?.to, "mods/metallum.jar")
        let bad = CofreScenario(name: "metal", version: "26.2", files: [.init(url: "https://example.com/x.jar", to: "mods/../x.jar")])
        XCTAssertThrowsError(try bad.validate())
    }

    func testInlineTextFileNeedsExactlyOneSource() throws {
        let s = try CofreScenario.load(Data(#"{"name":"nf","version":"26.2","loader":"neoforge","files":[{"text":"earlyWindowControl = false\n","to":"config/fml.toml"}]}"#.utf8))
        XCTAssertEqual(s.files.first?.text, "earlyWindowControl = false\n")
        let both = CofreScenario(name: "nf", version: "26.2", files: [.init(url: "https://example.com/a", text: "x", to: "config/a")])
        XCTAssertThrowsError(try both.validate())
        let neither = CofreScenario(name: "nf", version: "26.2", files: [.init(to: "config/a")])
        XCTAssertThrowsError(try neither.validate())
    }
}
