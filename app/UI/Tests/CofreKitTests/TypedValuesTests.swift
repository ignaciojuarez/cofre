import XCTest
@testable import CofreKit

final class TypedValuesTests: XCTestCase {
    func testOldRawValuesDecodeAndKeepWireSpelling() throws {
        XCTAssertEqual(try JSONDecoder().decode(RendererID.self, from: Data(#""mobileglues""#.utf8)), .mobileglues)
        XCTAssertEqual(try JSONDecoder().decode(GraphicsAPI.self, from: Data(#""auto""#.utf8)), .auto)
        XCTAssertEqual(try JSONDecoder().decode(JavaRuntimeID.self, from: Data(#""21""#.utf8)), .java21)
        XCTAssertEqual(try JSONDecoder().decode(VersionChannel.self, from: Data(#""beta""#.utf8)), .beta)
        XCTAssertEqual(try JSONDecoder().decode(RendererID.self, from: Data(#""Metal""#.utf8)), .metallum)
    }

    func testUnknownRendererSurvivesDecodeEncode() throws {
        let value = try JSONDecoder().decode(RendererID.self, from: Data(#""future-renderer""#.utf8))
        XCTAssertEqual(value, .custom("future-renderer"))
        XCTAssertEqual(String(data: try JSONEncoder().encode(value), encoding: .utf8), #""future-renderer""#)
    }

    func testPreferenceKeysKeepLegacyRawValues() {
        XCTAssertEqual(PreferenceKey.inputMode.rawValue, "cofre.input.mode")
        XCTAssertEqual(PreferenceKey.optionsBefore("abc").rawValue, "cofre.options.before.abc")
    }
}
