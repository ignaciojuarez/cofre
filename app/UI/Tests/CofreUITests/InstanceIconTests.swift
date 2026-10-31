#if canImport(UIKit)
    import XCTest
    @testable import CofreUI

    @MainActor
    final class InstanceIconTests: XCTestCase {

        func testModdedInstancesGetTheirLoadersIcon() {
            for loader in Loader.allCases where loader != .vanilla {
                XCTAssertEqual(InstanceIcon.automatic(id: "pack", loader: loader).glyph, loader.glyph)
            }
            XCTAssertEqual(Loader.neoforge.glyph, .neoforge)
        }

        // Pinned: a vanilla instance's block must never change between launches or app versions.
        func testVanillaBlockIsStable() {
            XCTAssertEqual(InstanceIcon.automatic(id: "vanilla", loader: .vanilla).glyph, .sand)
            XCTAssertEqual(InstanceIcon.automatic(id: "Vanilla 1", loader: .vanilla).glyph, .gravel)
            XCTAssertEqual(InstanceIcon.automatic(id: "Vanilla 2", loader: .vanilla).glyph, .log)
            let id = UUID().uuidString
            XCTAssertEqual(
                InstanceIcon.automatic(id: id, loader: .vanilla), InstanceIcon.automatic(id: id, loader: .vanilla))
        }

        func testNewVanillaInstancesSpreadAcrossTheBlocks() {
            let picked = Set((1...8).map { InstanceIcon.automatic(id: "Vanilla \($0)", loader: .vanilla).glyph })
            XCTAssertEqual(picked, Set(InstanceIcon.blocks))
            XCTAssertEqual(InstanceIcon.blocks.count, 8)
        }

        func testSummaryWithoutAnIconGetsTheAutomaticOne() {
            let i = InstanceSummary(id: "x", name: "X", loader: .quilt, gameVersion: "1.21.1")
            XCTAssertEqual(i.icon.glyph, .quilt)
        }

        func testPackPNGWinsThenThePick() {
            let png = Data([0x89, 0x50])
            XCTAssertEqual(InstanceIcon.resolve(png: png, picked: "dirt", id: "a", loader: .fabric).png, png)
            XCTAssertEqual(InstanceIcon.resolve(png: nil, picked: "bricks", id: "a", loader: .fabric).glyph, .bricks)
            XCTAssertEqual(InstanceIcon.resolve(png: nil, picked: "nope", id: "a", loader: .fabric).glyph, .fabric)
            XCTAssertEqual(InstanceIcon.resolve(png: nil, picked: nil, id: "a", loader: .forge).glyph, .forge)
        }

        // Every pixel letter in the new art has a color, and loader marks stay square.
        func testIconArtHasColors() {
            for g in InstanceIcon.choices {
                let palette = PixelArtColors.icons[g.rawValue] ?? [:]
                for ch in Set(g.rows.joined()) where !".@&c".contains(ch) {
                    XCTAssertNotNil(palette[ch], "\(g) is missing \(ch)")
                }
                XCTAssertEqual(g.rows.count, g.rows.map(\.count).max(), "\(g) isn't square")
            }
        }
    }
#endif
