import SwiftUI
import UIKit

// DESIGN_SYSTEM §1 and §5.2. One theme feeds SwiftUI and Air's UIKit screens.

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
    private final class Box: @unchecked Sendable { let lock = NSLock(); var theme = CofreTheme() }
    private static let box = Box()

    public var colorScheme: ColorScheme? { appearance == .auto ? nil : (appearance == .light ? .light : .dark) }
    public var interfaceStyle: UIUserInterfaceStyle { appearance == .auto ? .unspecified : (appearance == .light ? .light : .dark) }
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

public extension EnvironmentValues {
    @Entry var cofreTheme: CofreTheme = .standard
    @Entry var widthClass: WidthClass = .compact
    /// True when a pane was pushed onto a stack; `ColumnHeader` shows its back button only then.
    @Entry var isPushed: Bool = false
    /// Extra view a container asks the next `ColumnHeader` to show under its title (AdaptiveSplit's segmented fallback).
    @Entry var columnHeaderAccessory: AnyView? = nil
}

// MARK: - Colors

/// Dynamic `UIColor` tokens. Each resolves light/dark, Increase Contrast and the current accent at draw time.
public struct CofreUIColors: @unchecked Sendable {
    public let page = dyn(\.palette.page), side = dyn(\.palette.side), panel = dyn(\.palette.panel)
    public let raised = dyn(\.palette.raised), button = dyn(\.palette.button), buttonBevel = dyn(\.palette.buttonBevel)
    public let well = dyn(\.palette.well), bevel = dyn(\.palette.bevel), lip = dyn(\.palette.lip)
    public let outline = dyn(\.palette.outline, highContrast: \.palette.outlineHC)
    public let ink = dyn(\.palette.ink), inkSoft = dyn(\.palette.inkSoft)
    public let muted = dyn(\.palette.muted, highContrast: \.palette.inkSoft)
    public let success = dyn(\.palette.success), warn = dyn(\.palette.warn), danger = dyn(\.palette.danger), quilt = dyn(\.palette.quilt)
    public let accent = dyn(\.accent.accent), face = dyn(\.accent.face), faceBevel = dyn(\.accent.faceBevel)
    public let faceLip = dyn(\.accent.faceLip), onFace = dyn(\.accent.onFace)
    public let hover = UIColor { tc in
        let t = CofreTheme.current, light = tc.userInterfaceStyle == .light
        return UIColor(hex: light ? t.palette.ink.light : t.palette.ink.dark, alpha: light ? t.palette.hoverOpacity.light : t.palette.hoverOpacity.dark)
    }

    /// `tone` mixed into `panel` (or `well` for neutral). `amount` overrides the tone's default (banners use 0.16).
    public func tint(_ tone: Tone, amount: CGFloat? = nil) -> UIColor {
        if tone == .neutral { return well }
        let base = color(for: tone), mix = amount ?? tone.tintAmount, panel = self.panel
        return UIColor { tc in base.resolvedColor(with: tc).mixed(into: panel.resolvedColor(with: tc), amount: mix) }
    }

    public func color(for tone: Tone) -> UIColor {
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
    private let ui = UIColor.cofre
    public var page: Color { Color(uiColor: ui.page) }
    public var side: Color { Color(uiColor: ui.side) }
    public var panel: Color { Color(uiColor: ui.panel) }
    public var raised: Color { Color(uiColor: ui.raised) }
    public var button: Color { Color(uiColor: ui.button) }
    public var buttonBevel: Color { Color(uiColor: ui.buttonBevel) }
    public var well: Color { Color(uiColor: ui.well) }
    public var bevel: Color { Color(uiColor: ui.bevel) }
    public var lip: Color { Color(uiColor: ui.lip) }
    public var outline: Color { Color(uiColor: ui.outline) }
    public var ink: Color { Color(uiColor: ui.ink) }
    public var inkSoft: Color { Color(uiColor: ui.inkSoft) }
    public var muted: Color { Color(uiColor: ui.muted) }
    public var accent: Color { Color(uiColor: ui.accent) }
    public var face: Color { Color(uiColor: ui.face) }
    public var faceBevel: Color { Color(uiColor: ui.faceBevel) }
    public var faceLip: Color { Color(uiColor: ui.faceLip) }
    public var onFace: Color { Color(uiColor: ui.onFace) }
    public var success: Color { Color(uiColor: ui.success) }
    public var warn: Color { Color(uiColor: ui.warn) }
    public var danger: Color { Color(uiColor: ui.danger) }
    public var hover: Color { Color(uiColor: ui.hover) }
    public func tone(_ tone: Tone) -> Color { Color(uiColor: ui.color(for: tone)) }
    public func tint(_ tone: Tone, amount: CGFloat? = nil) -> Color { Color(uiColor: ui.tint(tone, amount: amount)) }
}

public extension UIColor { static let cofre = CofreUIColors() }

private func dyn(_ key: KeyPath<CofreTheme, ColorPair>, highContrast: KeyPath<CofreTheme, ColorPair>? = nil) -> UIColor {
    UIColor { tc in
        let t = CofreTheme.current
        let pair = (tc.accessibilityContrast == .high ? highContrast : nil).map { t[keyPath: $0] } ?? t[keyPath: key]
        return UIColor(hex: tc.userInterfaceStyle == .light ? pair.light : pair.dark)
    }
}
public extension Color { static let cofre = CofreColors() }

extension UIColor {
    func mixed(into other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1); other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r2 + (r1 - r2) * amount, green: g2 + (g1 - g2) * amount, blue: b2 + (b1 - b2) * amount, alpha: 1)
    }

    /// Hex string for Air's `general.*_color` prefs.
    func hexString(for style: UIUserInterfaceStyle = .dark) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
