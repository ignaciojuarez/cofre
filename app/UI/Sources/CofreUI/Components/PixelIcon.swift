import SwiftUI

// §2 #16 PixelIcon: 8×8-grid glyphs drawn in code (same art as the mockups). Decorative unless it's the only content.

public enum PixelGlyph: String, CaseIterable, Sendable {
    case grass, stone, ore, book, gear, play, bolt, cmd, key, shield, check, paper, chest, head, cross

    /// Row strings, one char per pixel, "." is transparent. "@" is the tint, "&" the tint shaded to 62%, "c" the foreground.
    var rows: [String] {
        switch self {
        case .grass: ["GGGGGGGG", "GgGGGgGG", "gGdGgGdg", "dDdDDdDd", "DdDDdDDD", "DDdDDDdD", "dDDDdDDd", "DDdDDDDD"]
        case .stone: ["SsSSdSSs", "SSsSSSsS", "dSSsSdSS", "SSSSsSSs", "SsdSSSsS", "sSSSsSdS", "SSsSSSSs", "SdSSsSSS"]
        case .ore: ["ssSsssSs", "s@@ssSss", "s@&sss@s", "ssssS@@s", "Sssss&@s", "s@@sssss", "s@&ssSss", "ssssssss"]
        case .book: [".PPPPPP.", "PppppppP", "PpYYYppP", "PppppppP", "PpYYpppP", "PppppppP", "PPPPPPPP", ".wwwwww."]
        case .gear: ["...gg...", ".g.GG.g.", "..GGGG..", "gGG..GGg", "gGG..GGg", "..GGGG..", ".g.GG.g.", "...gg..."]
        case .play: [".c......", ".cc.....", ".ccc....", ".cccc...", ".cccc...", ".ccc....", ".cc.....", ".c......"]
        case .bolt: ["....YYY.", "...YYY..", "..YYY...", ".YYYYYY.", "...YYY..", "..YYy...", ".YYy....", "Yy......"]
        case .cmd: ["OoOoOoOo", "oOOOOOOO", "OOggggOo", "oOgkkgOO", "OOgkkgOo", "oOggggOO", "OOOOOOOo", "oOoOoOoO"]
        case .key: ["..........", ".YYY......", "Y.y.Y.....", "Yy.yYYYYYY", "Y.y.Y..Y.Y", ".YYY......", ".........."]
        case .shield: ["SSSSSSSS", "SssssssS", "SsssssWS", "SssssWsS", "SWsssWsS", "SsWsWssS", ".SsWssS.", "..SSSS.."]
        case .check: ["......G", ".....GG", "G...GG.", "GG.GG..", ".GGG...", "..G...."]
        case .paper: ["WWWWW..", "WWWWWF.", "WllllWF", "WWWWWWW", "WllllWW", "WWWWWWW", "WlllWWW", "WWWWWWW"]
        case .chest: ["bbbbbbbb", "bBBBBBBb", "bBBBBBBb", "bbbYYbbb", "kkkYYkkk", "bBBBBBBb", "bBBBBBBb", "bbbbbbbb"]
        case .head: ["HHHHHHHH", "HHHHHHHH", "HSSSSSSH", "SEBSSBES", "SSSssSSS", "SSsMMsSS", "SSSSSSSS", "SSSSSSSS"]
        case .cross: ["R.....R", ".R...R.", "..R.R..", "...R...", "..R.R..", ".R...R.", "R.....R"]
        }
    }
}

public struct PixelIcon: View {
    let glyph: PixelGlyph, size: CGFloat, tint: Color?

    public init(_ glyph: PixelGlyph, size: CGFloat = 16, tint: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let rows = glyph.rows
        let palette = PixelArtColors.icons[glyph.rawValue] ?? [:]
        let tintColor = tint ?? Color(hex: PixelArtColors.oreTints["diamond"]!)
        Canvas { ctx, sz in
            drawPixels(rows, in: sz) { ch, rect in
                switch ch {
                case "@": ctx.fill(Path(rect), with: .color(tintColor))
                case "&":
                    ctx.fill(Path(rect), with: .color(tintColor))
                    ctx.fill(Path(rect), with: .color(.black.opacity(0.38)))
                case "c": ctx.fill(Path(rect), with: .foreground)
                default: if let hex = palette[ch] { ctx.fill(Path(rect), with: .color(Color(hex: hex))) }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityIgnoresInvertColors()
        .accessibilityHidden(true)
    }
}

/// Larger art in the PixelIcon recipe: one char per pixel, "." transparent, colors from tokens.
/// Each art pixel is `pixel` pt, so art lines up with a PixelScene drawn at the same scale.
public struct PixelArt: View {
    let rows: [String], palette: [Character: Color], pixel: CGFloat

    public init(_ rows: [String], palette: [Character: Color], pixel: CGFloat = 4) {
        self.rows = rows
        self.palette = palette
        self.pixel = pixel
    }

    public var body: some View {
        Canvas { ctx, sz in
            drawPixels(rows, in: sz) { ch, rect in if let c = palette[ch] { ctx.fill(Path(rect), with: .color(c)) } }
        }
        .frame(width: CGFloat(rows.map(\.count).max() ?? 0) * pixel, height: CGFloat(rows.count) * pixel)
        .accessibilityIgnoresInvertColors()
        .accessibilityHidden(true)
    }
}

/// Fits the grid into `size`, centered, and hands each non-"." pixel's rect to `fill`.
private func drawPixels(_ rows: [String], in size: CGSize, _ fill: (Character, CGRect) -> Void) {
    let h = rows.count
    let w = rows.map(\.count).max() ?? 1
    let k = min(size.width / CGFloat(w), size.height / CGFloat(h))
    let ox = (size.width - k * CGFloat(w)) / 2
    let oy = (size.height - k * CGFloat(h)) / 2
    for (y, row) in rows.enumerated() {
        for (x, ch) in row.enumerated() where ch != "." {
            fill(ch, CGRect(x: ox + CGFloat(x) * k, y: oy + CGFloat(y) * k, width: k + 0.01, height: k + 0.01))
        }
    }
}

/// Pending step mark (an empty square).
public struct PendingMark: View {
    public init() {}
    public var body: some View {
        Rectangle().strokeBorder(Color.cofre.muted, lineWidth: 2).frame(width: 12, height: 12).opacity(0.6)
            .accessibilityHidden(true)
    }
}
