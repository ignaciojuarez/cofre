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

/// One color token: a dark value and a light value.
public struct ColorPair: Sendable, Hashable {
    public let dark: UInt32
    public let light: UInt32
    public init(dark: UInt32, light: UInt32) {
        self.dark = dark
        self.light = light
    }
    public init(_ both: UInt32) { self.init(dark: both, light: both) }
}

/// Surface, text and status tokens. Accent tokens live in `AccentFamily`.
public struct Palette: Sendable, Hashable {
    public var page, side, panel, raised, button, buttonBevel, well, bevel, lip, outline, outlineHC: ColorPair
    public var ink, inkSoft, muted, success, warn, danger, quilt: ColorPair
    /// Hover overlay is `ink` at this opacity.
    public var hoverOpacity: (dark: Double, light: Double)
    /// Stone texture cells behind every screen.
    public var stone: (dark: [UInt32], light: [UInt32])

    public static func == (a: Palette, b: Palette) -> Bool { a.page == b.page && a.ink == b.ink && a.panel == b.panel }
    public func hash(into h: inout Hasher) {
        h.combine(page)
        h.combine(ink)
        h.combine(panel)
    }

    public static let purple = Palette(
        page: .init(dark: 0x0f0d17, light: 0xece7f7),
        side: .init(dark: 0x0b0a11, light: 0xe2dbf2),
        panel: .init(dark: 0x1a1727, light: 0xf8f6fd),
        raised: .init(dark: 0x221e34, light: 0xe9e3f8),
        button: .init(dark: 0x2b2641, light: 0xddd4f3),
        buttonBevel: .init(dark: 0x3d3560, light: 0xf4f0fe),
        well: .init(dark: 0x0c0b12, light: 0xf3f0fb),
        bevel: .init(dark: 0x342d52, light: 0xffffff),
        lip: .init(dark: 0x07060b, light: 0xc3b8e2),
        outline: .init(dark: 0x05040a, light: 0x2b2244),
        outlineHC: .init(dark: 0x8a82a3, light: 0x2b2244),
        ink: .init(dark: 0xecedf3, light: 0x1b1530),
        inkSoft: .init(dark: 0xc5c7d1, light: 0x3b3354),
        muted: .init(dark: 0xa29cb8, light: 0x585071),
        success: .init(dark: 0x45c27a, light: 0x136336),
        warn: .init(dark: 0xf0b84f, light: 0x7a4f00),
        danger: .init(dark: 0xf07a68, light: 0xa3301d),
        quilt: .init(0x5ad1e8),
        hoverOpacity: (0.08, 0.06),
        stone: ([0x0f0d17, 0x121020, 0x0d0b14, 0x151225], [0xece7f7, 0xe7e1f4, 0xe2dbf1, 0xefebf9])
    )
}

/// The four tokens an X07 accent swatch swaps. Pushed to Air's `general.accent_color` as `face`.
public struct AccentFamily: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public var face, faceBevel, faceLip, accent, onFace: ColorPair

    public static let purple = AccentFamily(
        id: "purple", name: "Amethyst",
        face: .init(0x5b3fd6), faceBevel: .init(dark: 0x8a74ff, light: 0x8069ef), faceLip: .init(0x3a2694),
        accent: .init(dark: 0x9a86ff, light: 0x5333c9), onFace: .init(0xffffff))
    public static let emerald = AccentFamily(
        id: "emerald", name: "Emerald",
        face: .init(0x1a7a43), faceBevel: .init(0x4cc27e), faceLip: .init(0x0f5a2f),
        accent: .init(dark: 0x57d58c, light: 0x136336), onFace: .init(0xffffff))
    public static let copper = AccentFamily(
        id: "copper", name: "Copper",
        face: .init(0xb4531f), faceBevel: .init(0xe0814a), faceLip: .init(0x7a3410),
        accent: .init(dark: 0xf09a62, light: 0x9a3f0e), onFace: .init(0xffffff))
    public static let diamond = AccentFamily(
        id: "diamond", name: "Diamond",
        face: .init(0x13788c), faceBevel: .init(0x3fb3c9), faceLip: .init(0x0a4c59),
        accent: .init(dark: 0x5ad1e8, light: 0x0d6475), onFace: .init(0xffffff))
    public static let redstone = AccentFamily(
        id: "redstone", name: "Redstone",
        face: .init(0xb02a2a), faceBevel: .init(0xe05a5a), faceLip: .init(0x6e1414),
        accent: .init(dark: 0xf07a68, light: 0xa3301d), onFace: .init(0xffffff))

    public static let all: [AccentFamily] = [.purple, .emerald, .copper, .diamond, .redstone]
}

/// Fixed colors used only inside pixel art (icons and scenes). Not themeable on purpose.
enum PixelArtColors {
    // PixelScene palettes, one per style. Skies stay dark at the top so white titles read on any crop.
    enum Falls {
        static let sky: [UInt32] = [0x0a0b24, 0x11143a, 0x1a1a4e, 0x24215f, 0x30296e, 0x3d327c, 0x4b3d8a]
        static let mesa: (UInt32, UInt32) = (0x2a2463, 0x3a3178)
        static let rock: [UInt32] = [0x231d40, 0x282147, 0x1f1a39, 0x2c2550]
        static let rockLit: UInt32 = 0x46397a, rockBack: (UInt32, UInt32) = (0x18142f, 0x221c40)
        static let grass: (UInt32, UInt32) = (0x3f9a55, 0x2a6b3d), vine: UInt32 = 0x1f5434
        static let water: [UInt32] = [0x2f8fb3, 0x5ad1e8, 0xa8ecf7, 0xe9fbff]
        static let pool: [UInt32] = [0x1f3a6e, 0x182c58, 0x112043, 0x0c1631]
        static let ripple: UInt32 = 0x3d63a0, mist: (UInt32, UInt32) = (0x6577b8, 0xa9b8ea)
        static let tree: (UInt32, UInt32, UInt32) = (0x1e5a3a, 0x2f7a4c, 0x2a1a14), firefly: UInt32 = 0xf0b84f
    }
    enum Geode {
        static let glow: [UInt32] = [0x3a1f70, 0x2e1858, 0x241347, 0x1c0f39, 0x150b2b, 0x0f081f]
        static let ledge: (UInt32, UInt32) = (0x170d2c, 0x2b1a52)
        static let rock: (UInt32, UInt32) = (0x0b0716, 0x33205e)
        static let crystal: [UInt32] = [0xe9d6ff, 0xb983ff, 0x8152e0, 0x5534b0]
        static let crystalDim: [UInt32] = [0x8a68cc, 0x6a4bab, 0x4d3489, 0x372466]
        static let tip: UInt32 = 0xfaf4ff, spark: UInt32 = 0xe8d8ff
        static let gold: (UInt32, UInt32) = (0xf0b84f, 0xa86e14)
    }
    enum Islands {
        static let sky: [UInt32] = [0x080b26, 0x0e1436, 0x161d4a, 0x20265c, 0x2b2e6a, 0x373576, 0x433d80]
        static let aurora: [UInt32] = [0x1e5a6a, 0x2c9486, 0x5fe0b0]
        static let cloud: [(UInt32, UInt32)] = [(0x2a2a62, 0x383880), (0x3b3a7e, 0x5a56a0)]
        static let grass: (UInt32, UInt32) = (0x6cbf3f, 0x45a03a), dirt: (UInt32, UInt32) = (0x7a5230, 0x5a3a22)
        static let stone: (UInt32, UInt32) = (0x3a3456, 0x2b2742), root: UInt32 = 0x4a3020
        static let leaf: (UInt32, UInt32, UInt32) = (0x5fc46a, 0x2f8f57, 0x1f6b3e), trunk: UInt32 = 0x5a3a22
        static let water: [UInt32] = [0x5ad1e8, 0xa8ecf7, 0xe9fbff]
        static let chest: (UInt32, UInt32, UInt32) = (0xa8642f, 0x6e3d17, 0xf0b84f)
    }
    enum Lake {
        static let sky: [UInt32] = [0x05071a, 0x0a0e28, 0x111638, 0x1a1c4a, 0x26245c, 0x342c6c]
        static let moon: (UInt32, UInt32) = (0xf1edff, 0xc4bdea), halo: UInt32 = 0x2e2c6e
        static let forest: [(UInt32, UInt32)] = [(0x232158, 0x2e2b6c), (0x0d0b26, 0x3a3882)]
        static let water: UInt32 = 0x0b0f2c, ripple: UInt32 = 0x323c86, glint: (UInt32, UInt32) = (0xb9b4f0, 0x6e69bd)
        static let shore: (UInt32, UInt32) = (0x08081a, 0x1d3a2e), reed: (UInt32, UInt32) = (0x1c4532, 0x6a4428)
        static let cabin: (UInt32, UInt32) = (0x0d0b22, 0x2a2152), window: UInt32 = 0xf0b84f
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
