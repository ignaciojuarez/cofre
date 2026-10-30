#if os(macOS)
    import AppKit
    import XCTest
    @testable import CofreUI

    /// The Mac pairing helper (Llave) reads the same tokens and fonts through AppKit.
    final class CofreUIMacTests: XCTestCase {
        func testTokensResolve() {
            let c = NSColor.cofre
            XCTAssertEqual(hex(c.page), 0x0f0d17)
            XCTAssertEqual(hex(c.face), 0x5b3fd6)
            XCTAssertNotEqual(hex(c.tint(.success)), hex(c.panel))
        }

        func testBundledFontsRegister() {
            XCTAssertTrue(CofreFonts.register())
            for name in ["PixelifySans-Bold", "PixelifySans-SemiBold", "Geist-Regular", "GeistMono-Regular"] {
                XCTAssertNotNil(NSFont(name: name, size: 12), name)
            }
        }

        private func hex(_ c: NSColor) -> UInt32 {
            let c = c.usingColorSpace(.sRGB)!
            return UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8
                | UInt32((c.blueComponent * 255).rounded())
        }
    }
#endif
