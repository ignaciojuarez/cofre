import SwiftUI

// §2 #1 Block and §1.4 geometry: 2 pt outline, bevel on top, lip below, square.

public enum BlockKind: Sendable, Hashable { case panel, raised, well, button, primary, tinted(Tone) }

public struct BlockBackground: View {
    let kind: BlockKind
    let lip: CGFloat
    let selected: Bool
    var flat = false
    var tabBar = false

    @Environment(\.cofreTheme) private var theme

    public init(_ kind: BlockKind = .panel, lip: CGFloat = 2, selected: Bool = false) {
        self.kind = kind; self.lip = lip; self.selected = selected
    }

    init(_ kind: BlockKind, lip: CGFloat, selected: Bool, flat: Bool) {
        self.init(kind, lip: lip, selected: selected); self.flat = flat
    }

    public var body: some View {
        let c = Color.cofre, m = theme.block
        let (fill, bevel, shade): (Color, Color?, Color?) = switch kind {
        case .panel: (selected ? c.raised : c.panel, c.bevel, c.lip)
        case .raised: (c.raised, c.bevel, c.lip)
        case .well: (c.well, nil, nil)
        case .button: (c.button, c.buttonBevel, c.lip)
        case .primary: (c.face, c.faceBevel, c.faceLip)
        case .tinted(let tone): (c.tint(tone), c.bevel, c.lip)
        }
        Rectangle().fill(fill)
            .overlay(alignment: .top) {
                if let bevel, !flat { bevel.frame(height: m.bevel).padding([.horizontal, .top], m.outline) }
            }
            .overlay(alignment: .bottom) {
                if let shade, !flat, lip > 0 { shade.frame(height: lip).padding([.horizontal, .bottom], m.outline) }
            }
            .overlay(alignment: .leading) {
                if selected { c.accent.frame(width: m.selectionBar).padding(.vertical, m.outline).padding(.leading, m.outline) }
            }
            .overlay { Rectangle().strokeBorder(c.outline, lineWidth: m.outline) }
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Puts a block behind the view (§2 #1).
    func block(_ kind: BlockKind = .panel, lip: CGFloat = 2, selected: Bool = false) -> some View {
        background(BlockBackground(kind, lip: lip, selected: selected))
    }

    /// Large blocks (rows, cards): hover overlay only, no pointer morph (§2 shared states).
    func blockHover() -> some View { modifier(BlockHover()) }

    /// Accent ring 2 pt outside the outline, square. Turns the system focus effect off.
    func blockFocusRing() -> some View { modifier(FocusRing()) }

    /// Small controls: hover overlay plus the pointer morphing to the rectangle. The Mac keeps its arrow pointer.
    @ViewBuilder func blockPointer() -> some View {
        #if os(iOS)
        contentShape(.hoverEffect, Rectangle()).hoverEffect(.highlight)
        #else
        self
        #endif
    }

    /// Visual can be smaller than 44 pt; the hit area never is (§1.3).
    func minimumHitArea(_ size: CGFloat = 44) -> some View { modifier(HitArea(size: size)) }
}

struct BlockHover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .overlay { if hovering { Color.cofre.hover.allowsHitTesting(false) } }
            .onHover { hovering = $0 }
    }
}

struct FocusRing: ViewModifier {
    @Environment(\.isFocused) private var focused
    @Environment(\.cofreTheme) private var theme
    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if focused {
                    Rectangle().strokeBorder(Color.cofre.accent, lineWidth: theme.block.focusRing)
                        .padding(-(theme.block.focusRing + theme.block.focusOffset))
                        .allowsHitTesting(false)
                }
            }
    }
}

struct HitArea: ViewModifier {
    let size: CGFloat
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { g in
                let dx = max(0, (size - g.size.width) / 2), dy = max(0, (size - g.size.height) / 2)
                Color.clear.contentShape(Rectangle().inset(by: -max(dx, dy)))
            }
        }
    }
}

// MARK: - Page background (stone texture)

/// Window background: `page` plus the 2 pt stone texture tiled at 128 pt.
public struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        Color.cofre.page.overlay {
            Image(decorative: StoneTexture.image(light: scheme == .light), scale: 0.5)
                .resizable(resizingMode: .tile)
                .opacity(0.9)
                .accessibilityIgnoresInvertColors()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum StoneTexture {
    @MainActor private static var cache: [Bool: CGImage] = [:]

    /// 64 px bitmap, shown at scale 0.5 so a tile is 128 pt.
    @MainActor static func image(light: Bool) -> CGImage {
        if let hit = cache[light] { return hit }
        let pal = light ? CofreTheme.current.palette.stone.light : CofreTheme.current.palette.stone.dark
        var rng = Mulberry32(seed: 5)
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // 32×32 art pixels, each drawn 4× (rows from the top, like the mockups).
        for y in stride(from: 0, to: 32, by: 2) {
            for x in stride(from: 0, to: 32, by: 2) {
                let i = Int(rng.next() * rng.next() * Double(pal.count) * 1.6) % pal.count
                ctx.setFillColor(PlatformColor(hex: pal[i]).cgColor)
                ctx.fill(CGRect(x: x * 2, y: 60 - y * 2, width: 4, height: 4))
            }
        }
        let img = ctx.makeImage()!
        cache[light] = img
        return img
    }
}

/// Same seeded generator as the mockups (`rng` in ipad.html), so scenes match.
struct Mulberry32 {
    var a: UInt32
    init(seed: UInt32) { a = seed }
    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = UInt32(a)
        t = (t ^ (t >> 15)) &* (1 | t)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296
    }
}
