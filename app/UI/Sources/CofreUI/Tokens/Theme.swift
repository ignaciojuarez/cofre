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

public struct CofreTheme: Sendable {
    public var space = Spacing()
    public var block = BlockMetrics()
    public var motion = Motion()
    public init() {}
    public static let standard = CofreTheme()
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
    @Entry public var widthClass: WidthClass = .compact
    /// True when a pane was pushed onto a stack; `ColumnHeader` shows its back button only then.
    @Entry public var isPushed: Bool = false
    /// Extra view a container asks the next `ColumnHeader` to show under its title (AdaptiveSplit's segmented fallback).
    @Entry public var columnHeaderAccessory: AnyView? = nil
}

// MARK: - Colors

extension CofreUIColors {
    /// `tone` mixed into `panel` (or `well` for neutral). `amount` overrides the tone's default (banners use 0.16).
    public func tint(_ tone: Tone, amount: CGFloat? = nil) -> PlatformColor {
        tone == .neutral ? well : color(for: tone).mixed(into: panel, amount: amount ?? tone.tintAmount)
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

/// SwiftUI wrappers around the same `UIColor` tokens, so both stacks draw identical values.
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
}
