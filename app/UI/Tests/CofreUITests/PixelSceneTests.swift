import XCTest

@testable import CofreUI

/// PixelScene art: same seed, same picture; every pixel painted; every size the app asks for renders.
final class PixelSceneTests: XCTestCase {
    private let sizes = [(240, 110), (200, 140), (240, 84), (200, 70), (240, 160), (160, 60), (130, 66), (24, 12)]

    func testEveryStyleIsDeterministicAndFullyPainted() {
        for style in PixelScene.Style.allCases {
            for (w, h) in sizes {
                let a = SceneArt.render(style, seed: 11, w: w, h: h)
                XCTAssertEqual(a, SceneArt.render(style, seed: 11, w: w, h: h), "\(style) \(w)x\(h)")
                XCTAssertFalse(a.contains(0), "\(style) \(w)x\(h) left unpainted pixels")
            }
            XCTAssertNotEqual(
                SceneArt.render(style, seed: 3, w: 240, h: 110), SceneArt.render(style, seed: 7, w: 240, h: 110),
                "\(style) ignores the seed")
        }
    }

    func testTopStaysDarkForWhiteTitles() {
        for style in PixelScene.Style.allCases {
            let px = SceneArt.render(style, seed: 11, w: 240, h: 110)
            let luma = px.prefix(240 * 10).map { c in
                0.2126 * Double(c >> 16 & 0xff) + 0.7152 * Double(c >> 8 & 0xff) + 0.0722 * Double(c & 0xff)
            }
            XCTAssertLessThan(luma.reduce(0, +) / Double(luma.count), 80, "\(style)")
        }
    }
}
