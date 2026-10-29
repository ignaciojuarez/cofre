import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

// DESIGN_SYSTEM §1 and §5.2. One theme feeds SwiftUI and Air's UIKit screens (and the Mac helper's AppKit window).

public struct Spacing: Sendable {
    public var s1: CGFloat = 2, s2: CGFloat = 4, s3: CGFloat = 6, s4: CGFloat = 8, s5: CGFloat = 10
    public var s6: CGFloat = 12, s7: CGFloat = 16, s8: CGFloat = 20, s9: CGFloat = 28
    public var hit: CGFloat = 44, rowMin: CGFloat = 44, field: CGFloat = 38
    public var sidebar: CGFloat = 248, rail: CGFloat = 76, tabBar: CGFloat = 56
    public var readable: CGFloat = 720, card: CGFloat = 560, aside: CGFloat = 380, inspector: CGFloat = 360
    public init() {}
}

public struct BlockMetrics: Sendable {
    public var outline: CGFloat = 2, bevel: CGFloat = 2, lip: CGFloat = 2
    public var buttonLip: CGFloat = 4, smallButtonLip: CGFloat = 3, pressedLip: CGFloat = 1, pressDrop: CGFloat = 2
    public var selectionBar: CGFloat = 4, tabSelectionBar: CGFloat = 3, focusRing: CGFloat = 2, focusOffset: CGFloat = 2
    public var disabledOpacity: Double = 0.42
    public init() {}
}

public struct Motion: Sendable {
    public var press = 0.09, toggle = 0.12, select = 0.12, column = 0.22, reducedCrossfade = 0.15
    public init() {}
}

public enum Appearance: String, CaseIterable, Codable, Sendable { case dark, light, auto }

public struct CofreTheme: Sendable {
    public var palette: Palette = .purple
    public var accent: AccentFamily = .purple
    public var appearance: Appearance = .dark
    public var space = Spacing()
    public var block = BlockMetrics()
    public var motion = Motion()
    public init() {}
    public static let standard = CofreTheme()

    /// The theme dynamic colors resolve against. Set it, then re-render (the root view keys on `accent.id`).
    public static var current: CofreTheme {
        get { box.lock.withLock { box.theme } }
        set { box.lock.withLock { box.theme = newValue } }
    }
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var theme = CofreTheme()
    }
    private static let box = Box()

    public var colorScheme: ColorScheme? { appearance == .auto ? nil : (appearance == .light ? .light : .dark) }
    #if canImport(UIKit)
        public var interfaceStyle: UIUserInterfaceStyle {
            appearance == .auto ? .unspecified : (appearance == .light ? .light : .dark)
        }
    #endif
}

/// Status and loader tones. Tints are the tone mixed into `panel` (§1.1).
public enum Tone: Sendable, Hashable {
    case neutral, accent, success, warn, danger, fabric, forge, neoforge, quilt

    var tintAmount: CGFloat {
        switch self {
        case .neutral: 0
        case .accent, .fabric, .quilt: 0.22
        case .success, .forge, .neoforge: 0.24
        case .warn, .danger: 0.26
        }
    }
}

public enum WidthClass: Int, Comparable, Sendable {
    case compact, medium, expanded
    public static func < (a: WidthClass, b: WidthClass) -> Bool { a.rawValue < b.rawValue }

    /// §3.1: size class first, then the shell's measured width. Never the device.
    public static func resolve(sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> WidthClass {
        if sizeClass == .compact { return .compact }
        return width >= 1100 ? .expanded : .medium
    }
}

extension EnvironmentValues {
    @Entry public var cofreTheme: CofreTheme = .standard
    @Entry public var widthClass: WidthClass = .compact
    /// True when a pane was pushed onto a stack; `ColumnHeader` shows its back button only then.
    @Entry public var isPushed: Bool = false
    /// Extra view a container asks the next `ColumnHeader` to show under its title (AdaptiveSplit's segmented fallback).
    @Entry public var columnHeaderAccessory: AnyView? = nil
}

// MARK: - Colors

/// Dynamic `UIColor` (`NSColor` on the Mac) tokens. Each resolves light/dark, Increase Contrast and the current accent at draw time.
public struct CofreUIColors: @unchecked Sendable {
    public let page = dyn(\.palette.page), side = dyn(\.palette.side), panel = dyn(\.palette.panel)
    public let raised = dyn(\.palette.raised), button = dyn(\.palette.button), buttonBevel = dyn(\.palette.buttonBevel)
    public let well = dyn(\.palette.well), bevel = dyn(\.palette.bevel), lip = dyn(\.palette.lip)
    public let outline = dyn(\.palette.outline, highContrast: \.palette.outlineHC)
    public let ink = dyn(\.palette.ink), inkSoft = dyn(\.palette.inkSoft)
    public let muted = dyn(\.palette.muted, highContrast: \.palette.inkSoft)
    public let success = dyn(\.palette.success), warn = dyn(\.palette.warn), danger = dyn(\.palette.danger),
        quilt = dyn(\.palette.quilt)
    public let accent = dyn(\.accent.accent), face = dyn(\.accent.face), faceBevel = dyn(\.accent.faceBevel)
    public let faceLip = dyn(\.accent.faceLip), onFace = dyn(\.accent.onFace)
    public let hover = PlatformColor.dynamic { light, _ in
        let t = CofreTheme.current
        return PlatformColor(
            hex: light ? t.palette.ink.light : t.palette.ink.dark,
            alpha: light ? t.palette.hoverOpacity.light : t.palette.hoverOpacity.dark)
    }

    /// `tone` mixed into `panel` (or `well` for neutral). `amount` overrides the tone's default (banners use 0.16).
    public func tint(_ tone: Tone, amount: CGFloat? = nil) -> PlatformColor {
        if tone == .neutral { return well }
        let base = color(for: tone)
        let mix = amount ?? tone.tintAmount
        let panel = self.panel
        return .dynamic { light, hc in
            base.resolved(light: light, highContrast: hc).mixed(
                into: panel.resolved(light: light, highContrast: hc), amount: mix)
        }
    }

    public func color(for tone: Tone) -> PlatformColor {
        switch tone {
        case .neutral: inkSoft
        case .accent, .fabric: accent
        case .success: success
        case .warn, .forge: warn
        case .danger, .neoforge: danger
        case .quilt: quilt
        }
    }

}

/// SwiftUI wrappers around the same `UIColor` tokens, so both stacks resolve identical values.
public struct CofreColors: @unchecked Sendable {
    private let ui = PlatformColor.cofre
    public var page: Color { Color(platform: ui.page) }
    public var side: Color { Color(platform: ui.side) }
    public var panel: Color { Color(platform: ui.panel) }
    public var raised: Color { Color(platform: ui.raised) }
    public var button: Color { Color(platform: ui.button) }
    public var buttonBevel: Color { Color(platform: ui.buttonBevel) }
    public var well: Color { Color(platform: ui.well) }
    public var bevel: Color { Color(platform: ui.bevel) }
    public var lip: Color { Color(platform: ui.lip) }
    public var outline: Color { Color(platform: ui.outline) }
    public var ink: Color { Color(platform: ui.ink) }
    public var inkSoft: Color { Color(platform: ui.inkSoft) }
    public var muted: Color { Color(platform: ui.muted) }
    public var accent: Color { Color(platform: ui.accent) }
    public var face: Color { Color(platform: ui.face) }
    public var faceBevel: Color { Color(platform: ui.faceBevel) }
    public var faceLip: Color { Color(platform: ui.faceLip) }
    public var onFace: Color { Color(platform: ui.onFace) }
    public var success: Color { Color(platform: ui.success) }
    public var warn: Color { Color(platform: ui.warn) }
    public var danger: Color { Color(platform: ui.danger) }
    public var hover: Color { Color(platform: ui.hover) }
    public func tone(_ tone: Tone) -> Color { Color(platform: ui.color(for: tone)) }
    public func tint(_ tone: Tone, amount: CGFloat? = nil) -> Color { Color(platform: ui.tint(tone, amount: amount)) }
}

extension PlatformColor { public static let cofre = CofreUIColors() }

private func dyn(_ key: KeyPath<CofreTheme, ColorPair>, highContrast: KeyPath<CofreTheme, ColorPair>? = nil)
    -> PlatformColor
{
    .dynamic { light, hc in
        let t = CofreTheme.current
        let pair = (hc ? highContrast : nil).map { t[keyPath: $0] } ?? t[keyPath: key]
        return PlatformColor(hex: light ? pair.light : pair.dark)
    }
}
extension Color { public static let cofre = CofreColors() }

extension Color {
    init(platform color: PlatformColor) {
        #if canImport(UIKit)
            self.init(uiColor: color)
        #else
            self.init(nsColor: color)
        #endif
    }
}

extension PlatformColor {
    /// Resolves at draw time from light/dark and Increase Contrast, the only traits tokens read.
    static func dynamic(_ make: @escaping (_ light: Bool, _ highContrast: Bool) -> PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
            UIColor { tc in make(tc.userInterfaceStyle == .light, tc.accessibilityContrast == .high) }
        #else
            // AppKit can't build a high-contrast appearance on demand, so contrast reads the system setting.
            NSColor(name: nil) {
                make(
                    $0.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            }
        #endif
    }

    /// This color for one appearance, as plain RGB. On the Mac, contrast follows the system setting.
    func resolved(light: Bool, highContrast: Bool) -> PlatformColor {
        #if canImport(UIKit)
            resolvedColor(
                with: UITraitCollection {
                    $0.userInterfaceStyle = light ? .light : .dark
                    $0.accessibilityContrast = highContrast ? .high : .normal
                })
        #else
            var out = self
            NSAppearance(named: light ? .aqua : .darkAqua)?.performAsCurrentDrawingAppearance {
                out = usingColorSpace(.sRGB) ?? self
            }
            return out
        #endif
    }

    func mixed(into other: PlatformColor, amount: CGFloat) -> PlatformColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return PlatformColor(
            red: r2 + (r1 - r2) * amount, green: g2 + (g1 - g2) * amount, blue: b2 + (b1 - b2) * amount, alpha: 1)
    }

    #if canImport(UIKit)
        /// Hex string for Air's `general.*_color` prefs.
        func hexString(for style: UIUserInterfaceStyle = .dark) -> String {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
        }
    #endif
}
