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
    static let sky: [UInt32] = [
        0x0a0f2c, 0x121338, 0x1d1648, 0x2a1a58, 0x3d1f68, 0x5a2774, 0x7e3279, 0xa6437c, 0xcc5a78, 0xe8786a, 0xf2985c,
        0xf6b85a,
    ]
    static let starBright: UInt32 = 0xffffff, starDim: UInt32 = 0x8c86c4
    static let sunCore: UInt32 = 0xfff2c4, sunRim: UInt32 = 0xffd27a
    static let cloud: UInt32 = 0x4a3478, cloudTop: UInt32 = 0x6a4a98
    static let hillFar: (UInt32, UInt32) = (0x3a2470, 0x53359a)
    static let hillMid: (UInt32, UInt32) = (0x241a4d, 0x33276a)
    static let ground: (UInt32, UInt32) = (0x130f2e, 0x2b6b3a)
    static let tree: UInt32 = 0x0d0a22
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
