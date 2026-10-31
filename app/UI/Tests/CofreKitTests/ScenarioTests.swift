import XCTest
@testable import CofreKit

final class ScenarioTests: XCTestCase {
    func testDefaultsAndValidation() throws {
        let s = try CofreScenario.load(Data(#"{"name":"fab","version":"1.21.1","loader":"fabric","mods":["sodium"]}"#.utf8))
        XCTAssertEqual(s.renderer, "auto"); XCTAssertTrue(s.launch)
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
}
