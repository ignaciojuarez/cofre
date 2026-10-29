#if os(macOS)
import AppKit
import XCTest
@testable import CofreUI

/// The Mac pairing helper (Llave) reads the same tokens and fonts through AppKit.
final class CofreUIMacTests: XCTestCase {
    func testTokensResolvePerAppearance() {
        let c = NSColor.cofre
        XCTAssertEqual(hex(c.page.resolved(light: false, highContrast: false)), 0x0f0d17)
        XCTAssertEqual(hex(c.page.resolved(light: true, highContrast: false)), 0xece7f7)
        XCTAssertEqual(hex(c.ink.resolved(light: true, highContrast: false)), 0x1b1530)
        XCTAssertEqual(hex(c.face.resolved(light: false, highContrast: false)), 0x5b3fd6)
        XCTAssertNotEqual(hex(c.tint(.success).resolved(light: false, highContrast: false)), hex(c.panel.resolved(light: false, highContrast: false)))
    }

    func testBundledFontsRegister() {
        XCTAssertTrue(CofreFonts.register())
        for name in ["PixelifySans-Bold", "PixelifySans-SemiBold", "Geist-Regular", "GeistMono-Regular"] {
            XCTAssertNotNil(NSFont(name: name, size: 12), name)
        }
    }

    private func hex(_ c: NSColor) -> UInt32 {
        let c = c.usingColorSpace(.sRGB)!
        return UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8 | UInt32((c.blueComponent * 255).rounded())
    }
}
#endif
