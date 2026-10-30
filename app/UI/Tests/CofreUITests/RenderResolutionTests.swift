import XCTest

@testable import CofreUI

final class RenderResolutionTests: XCTestCase {
    let iPadMini = RenderResolution(width: 1488, height: 2266)  // portrait nativeBounds
    let iPhone17Pro = RenderResolution(width: 1206, height: 2622)
    let iPhone16 = RenderResolution(width: 1179, height: 2556)

    func testLandscapeSizes() {
        XCTAssertEqual(iPadMini.size(1), "2266 × 1488")
        XCTAssertEqual(iPadMini.size(0.5), "1133 × 744")
        XCTAssertEqual(iPhone17Pro.size(1.0 / 3), "874 × 402")
        // Air stores a float percentage.
        XCTAssertEqual(iPhone17Pro.size(Double(Float(100.0 / 3)) / 100), "874 × 402")
    }

    func testBatteryOnlyWhereThirdIsExact() {
        XCTAssertEqual(iPhone17Pro.presets, [.full, .balanced, .battery])
        XCTAssertEqual(iPadMini.presets, [.full, .balanced])
        XCTAssertTrue(iPhone17Pro.isSharp(.battery))
        XCTAssertFalse(iPadMini.isSharp(.battery))
    }

    func testSharpOnlyForWholeDivisors() {
        XCTAssertTrue(iPadMini.isSharp(.full))
        XCTAssertTrue(iPadMini.isSharp(.balanced))
        XCTAssertFalse(iPhone16.isSharp(.balanced), "1179 rows can't halve evenly")
    }

    func testMatchingSavedScaleToPreset() {
        XCTAssertEqual(iPadMini.preset(for: 1), .full)
        XCTAssertEqual(iPadMini.preset(for: 0.25 + 5 * 0.05), .balanced, "a slider step lands on ½")
        XCTAssertEqual(iPhone17Pro.preset(for: Double(Float(100.0 / 3)) / 100), .battery)
        XCTAssertNil(iPadMini.preset(for: 1.0 / 3), "Battery isn't offered here, so it's Custom")
        XCTAssertNil(iPadMini.preset(for: 0.7))
        XCTAssertNil(iPadMini.preset(for: 0.35))
    }

    func testLabels() {
        XCTAssertEqual(iPadMini.label(0.5), "Balanced · 1133 × 744")
        XCTAssertEqual(iPadMini.label(0.7), "70% · 1586 × 1042")
    }
}
