import XCTest

@testable import CofreUI

/// PixelScene art: same seed, same picture; every pixel painted; every size the app asks for renders.
final class PixelSceneTests: XCTestCase {
    private let sizes = [(240, 110), (200, 140), (240, 84), (200, 70), (240, 160), (160, 60), (130, 66), (24, 12)]

    func testDeterministicAndFullyPainted() {
        for (w, h) in sizes {
            let a = SceneArt.render(seed: 11, w: w, h: h)
            XCTAssertEqual(a, SceneArt.render(seed: 11, w: w, h: h), "\(w)x\(h)")
            XCTAssertFalse(a.contains(0), "\(w)x\(h) left unpainted pixels")
        }
        XCTAssertNotEqual(SceneArt.render(seed: 3, w: 240, h: 110), SceneArt.render(seed: 7, w: 240, h: 110))
    }

    func testTopStaysDarkForWhiteTitles() {
        for seed: UInt32 in [3, 7, 11, 23] {
            let px = SceneArt.render(seed: seed, w: 240, h: 110)
            XCTAssertLessThan(luma(px.prefix(240 * 10)), 80, "seed \(seed)")
        }
    }

    /// The launch screen on iPhone shows only the middle third of its 200×140 scene; the moon must be in it.
    func testMoonStaysInTheMiddleThird() {
        for seed: UInt32 in 0..<40 {
            let px = SceneArt.render(seed: seed, w: 200, h: 140)
            let moon = PixelArtColors.Lake.moon.0
            let xs = px.indices.filter { px[$0] == moon && $0 / 200 < 70 }.map { $0 % 200 }
            XCTAssertFalse(xs.isEmpty, "seed \(seed) has no moon")
            XCTAssertGreaterThanOrEqual(xs.min() ?? 0, 67, "seed \(seed)")
            XCTAssertLessThanOrEqual(xs.max() ?? 200, 133, "seed \(seed)")
        }
    }

    private func luma(_ px: ArraySlice<UInt32>) -> Double {
        let l = px.map { c in
            0.2126 * Double(c >> 16 & 0xff) + 0.7152 * Double(c >> 8 & 0xff) + 0.0722 * Double(c & 0xff)
        }
        return l.reduce(0, +) / Double(l.count)
    }
}
