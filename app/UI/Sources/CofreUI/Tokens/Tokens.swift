import SwiftUI

#if canImport(UIKit)
    import UIKit
    /// What tokens resolve to: `UIColor` in the app, `NSColor` in the Mac helper.
    public typealias PlatformColor = UIColor
#else
    import AppKit
    public typealias PlatformColor = NSColor
#endif

// DESIGN_SYSTEM §1.1. This is the only file that writes hex values.

/// `UIColor` (`NSColor` on the Mac) tokens. Cofre has one look: dark, with the purple accent.
public struct CofreUIColors: @unchecked Sendable {
    public let page = token(0x0f0d17), side = token(0x0b0a11), panel = token(0x1a1727)
    public let raised = token(0x221e34), button = token(0x2b2641), buttonBevel = token(0x3d3560)
    public let well = token(0x0c0b12), bevel = token(0x342d52), lip = token(0x07060b)
    public let outline = token(0x05040a, highContrast: 0x8a82a3)
    public let ink = token(0xecedf3), inkSoft = token(0xc5c7d1)
    public let muted = token(0xa29cb8, highContrast: 0xc5c7d1)
    public let success = token(0x45c27a), warn = token(0xf0b84f), danger = token(0xf07a68), quilt = token(0x5ad1e8)
    public let accent = token(0x9a86ff), face = token(0x5b3fd6), faceBevel = token(0x8a74ff)
    public let faceLip = token(0x3a2694), onFace = token(0xffffff)
    /// `ink` at 8%.
    public let hover = PlatformColor(hex: 0xecedf3, alpha: 0.08)
    /// Stone texture cells behind every screen.
    static let stone: [UInt32] = [0x0f0d17, 0x121020, 0x0d0b14, 0x151225]
}

/// Increase Contrast swaps in `highContrast`; it's the only trait tokens read. On the Mac it follows the system setting.
private func token(_ hex: UInt32, highContrast: UInt32? = nil) -> PlatformColor {
    guard let highContrast else { return PlatformColor(hex: hex) }
    #if canImport(UIKit)
        return UIColor { PlatformColor(hex: $0.accessibilityContrast == .high ? highContrast : hex) }
    #else
        return NSColor(name: nil) { _ in
            PlatformColor(hex: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? highContrast : hex)
        }
    #endif
}

/// Fixed colors used only inside pixel art (icons and scenes).
enum PixelArtColors {
    // PixelScene: the moonlit lake. The sky stays dark at the top so white titles read on any crop.
    enum Lake {
        static let sky: [UInt32] = [0x05071a, 0x0a0e28, 0x111638, 0x1a1c4a, 0x26245c, 0x342c6c]
        static let moon: (UInt32, UInt32) = (0xf6f3ff, 0xc4bdea), halo: (UInt32, UInt32) = (0x2e2c6e, 0x4a4794)
        static let forest: [(UInt32, UInt32)] = [(0x232158, 0x2e2b6c), (0x0d0b26, 0x3a3882)]
        static let water: UInt32 = 0x0b0f2c, ripple: UInt32 = 0x323c86
        static let glint: [UInt32] = [0xf6f3ff, 0xc9c5f6, 0x8a85d0, 0x5a56a8]
        static let shore: (UInt32, UInt32) = (0x08081a, 0x1d3a2e), reed: (UInt32, UInt32) = (0x1c4532, 0x6a4428)
        static let cabin: (UInt32, UInt32) = (0x0d0b22, 0x2a2152)
        static let window: (UInt32, UInt32) = (0xffe08a, 0xf0b84f), glow: (UInt32, UInt32) = (0x4a3048, 0x94603a)
    }
    static let starBright: UInt32 = 0xffffff, starDim: UInt32 = 0x8c86c4
    static let controllerGlyph: UInt32 = 0x3a3550

    // PixelIcon palettes (from the mockups' ICONS table).
    static let icons: [String: [Character: UInt32]] = [
        "grass": ["G": 0x6cbf3f, "g": 0x4f9a2e, "d": 0x7a5230, "D": 0x946640],
        "stone": ["S": 0x8b8b93, "s": 0x6e6e78, "d": 0xa3a3ab],
        "ore": ["S": 0x8b8b93, "s": 0x6e6e78],
        "book": ["P": 0x5b3fd6, "p": 0x8a74ff, "Y": 0xf0b84f, "w": 0xecedf3],
        "gear": ["g": 0x8f88a8, "G": 0xc5c7d1],
        "bolt": ["Y": 0xf0b84f, "y": 0xc98a1c],
        "cmd": ["o": 0xc98244, "O": 0x8a5226, "g": 0xb9bcc4, "k": 0x2b2b33],
        "key": ["Y": 0xf0b84f, "y": 0xb27a12],
        "shield": ["S": 0x45c27a, "s": 0x2f8f57, "W": 0xecedf3],
        "check": ["G": 0x45c27a],
        "paper": ["W": 0xecedf3, "l": 0xa29cb8, "F": 0xc5c7d1],
        "chest": ["B": 0xa8642f, "b": 0x6e3d17, "Y": 0xf0b84f, "k": 0x2b1608],
        "head": ["H": 0x3b2a1a, "S": 0xc99a74, "s": 0xb0805a, "E": 0xecedf3, "B": 0x4a5bd6, "M": 0x7a4a3a],
        "cross": ["R": 0xf07a68],
        "dirt": ["D": 0x8a5a36, "d": 0x6a4326, "l": 0xa6764c],
        "cobble": ["c": 0xb0b0b6, "C": 0x88888f, "k": 0x55555c],
        "planks": ["P": 0xb88a50, "p": 0x8a6436, "k": 0x6e4c28, "h": 0xcfa266],
        "sand": ["S": 0xe2d29a, "s": 0xcdb97e, "l": 0xf2e8bc],
        "gravel": ["g": 0x8c8580, "G": 0x6e6762, "l": 0xaea8a3, "k": 0x4e4846],
        "log": ["b": 0x5e4228, "P": 0xc09456, "r": 0x9a703e],
        "bricks": ["R": 0xb0563c, "r": 0x8c402c, "m": 0xcdc2b6],
        "fabric": ["o": 0x38342a, "h": 0xf0e8d0, "F": 0xdccfae, "f": 0xbfb08c, "s": 0x9c8f6c],
        "quilt": ["P": 0x9b4dff, "M": 0xd63fe8, "B": 0x35a9ff, "b": 0x4d5cff, "V": 0x8a3dff],
        "forge": ["N": 0x1f2d50, "W": 0xeef1f6, "w": 0xa9b3c4],
        "neoforge": ["E": 0x6b3a22, "e": 0xa8603a, "O": 0xe86a2c, "o": 0xb84a1a, "W": 0xf6f0e6, "k": 0x2a1a14],
    ]
    /// Ore tints used by sample data and instance icons.
    static let oreTints: [String: UInt32] = [
        "gold": 0xf0b84f, "redstone": 0xf07a68, "diamond": 0x5ad1e8, "amethyst": 0xb07bff, "emerald": 0x45c27a,
        "copper": 0xf08a3a, "lapis": 0x9a86ff,
    ]
}

extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

extension Color {
    /// A fixed pixel-art color. UI uses `Color.cofre` tokens instead.
    init(hex: UInt32) { self.init(platform: PlatformColor(hex: hex)) }
}
