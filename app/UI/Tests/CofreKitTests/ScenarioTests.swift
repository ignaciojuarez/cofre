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
}
