import SwiftUI

// §2 #2 BlockButton. One block recipe; roles swap fill, bevel, lip and ink.

public struct BlockButtonStyle: ButtonStyle {
    public enum Role: Sendable { case primary, secondary, ghost, destructive, ghostDestructive }
    public enum Size: Sendable { case small, regular, large }

    let role: Role, size: Size, fullWidth: Bool

    public init(_ role: Role = .secondary, size: Size = .regular, fullWidth: Bool = true) {
        self.role = role; self.size = size; self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        BlockButtonBody(configuration: configuration, role: role, size: size, fullWidth: fullWidth)
    }
}

public extension ButtonStyle where Self == BlockButtonStyle {
    static func block(_ role: BlockButtonStyle.Role = .secondary, size: BlockButtonStyle.Size = .regular, fullWidth: Bool? = nil) -> Self {
        BlockButtonStyle(role, size: size, fullWidth: fullWidth ?? (size != .small))
    }
}

private struct BlockButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: BlockButtonStyle.Role, size: BlockButtonStyle.Size, fullWidth: Bool

    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cofreTheme) private var theme
    @State private var hovering = false

    var body: some View {
        let m = theme.block, pressed = configuration.isPressed && enabled
        let ghost = role == .ghost || role == .ghostDestructive
        let lip: CGFloat = !enabled || ghost ? 0 : pressed ? m.pressedLip : (size == .small ? m.smallButtonLip : m.buttonLip)
        let height: CGFloat = ghost ? 34 : size == .small ? 30 : size == .large ? 50 : 42

        configuration.label
            .cofreFont(size == .large ? .buttonL : size == .small ? .buttonS : .button)
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, size == .small ? 10 : 14)
            .padding(.bottom, lip > 1 ? lip - 1 : 0)
            .offset(y: pressed && !reduceMotion ? m.pressDrop : 0)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background {
                if !ghost {
                    ButtonFace(role: role, lip: lip, flat: !enabled, hovering: hovering, darken: pressed && reduceMotion)
                } else if hovering {
                    Color.cofre.hover
                }
            }
            .contentShape(Rectangle().inset(by: -max(0, (44 - height) / 2)))
            .contentShape(.hoverEffect, Rectangle())
            .hoverEffect(.highlight)
            .onHover { hovering = $0 }
            .opacity(enabled ? 1 : m.disabledOpacity)
            .blockFocusRing()
            .animation(pressed ? nil : .linear(duration: theme.motion.press), value: pressed)
    }

    private var ink: Color {
        switch role {
        case .primary: .cofre.onFace
        case .secondary: .cofre.ink
        case .ghost: .cofre.muted
        case .destructive, .ghostDestructive: .cofre.danger
        }
    }
}

private struct ButtonFace: View {
    let role: BlockButtonStyle.Role, lip: CGFloat, flat: Bool, hovering: Bool, darken: Bool
    var body: some View {
        BlockBackground(role == .primary ? .primary : .button, lip: lip, selected: false, flat: flat)
            .overlay { if hovering { Color.cofre.hover.padding(2) } }
            .overlay { if darken { Color.black.opacity(0.18).padding(2) } }
    }
}

/// Convenience button: optional pixel icon, loading state (Spinner replaces the icon, label stays).
public struct BlockButton: View {
    let title: Text, icon: PixelGlyph?, iconTint: Color?, role: BlockButtonStyle.Role, size: BlockButtonStyle.Size
    let fullWidth: Bool?, isLoading: Bool, action: () -> Void

    public init(_ title: LocalizedStringKey, icon: PixelGlyph? = nil, iconTint: Color? = nil, role: BlockButtonStyle.Role = .secondary,
                size: BlockButtonStyle.Size = .regular, fullWidth: Bool? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.init(text: Text(title), icon: icon, iconTint: iconTint, role: role, size: size, fullWidth: fullWidth, isLoading: isLoading, action: action)
    }

    @_disfavoredOverload
    public init(_ title: String, icon: PixelGlyph? = nil, iconTint: Color? = nil, role: BlockButtonStyle.Role = .secondary,
                size: BlockButtonStyle.Size = .regular, fullWidth: Bool? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.init(text: Text(verbatim: title), icon: icon, iconTint: iconTint, role: role, size: size, fullWidth: fullWidth, isLoading: isLoading, action: action)
    }

    init(text: Text, icon: PixelGlyph?, iconTint: Color?, role: BlockButtonStyle.Role, size: BlockButtonStyle.Size,
         fullWidth: Bool?, isLoading: Bool, action: @escaping () -> Void) {
        self.title = text; self.icon = icon; self.iconTint = iconTint; self.role = role; self.size = size
        self.fullWidth = fullWidth; self.isLoading = isLoading; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    Spinner(size: size == .small ? 11 : 14)
                } else if let icon {
                    PixelIcon(icon, size: size == .small ? 11 : size == .large ? 18 : 15, tint: iconTint).accessibilityHidden(true)
                }
                title
            }
        }
        .buttonStyle(.block(role, size: size, fullWidth: fullWidth))
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

/// Icon-only block button. Needs an accessibility label.
public struct IconButton: View {
    let glyph: PixelGlyph, label: LocalizedStringKey, size: BlockButtonStyle.Size, action: () -> Void
    public init(_ glyph: PixelGlyph, label: LocalizedStringKey, size: BlockButtonStyle.Size = .small, action: @escaping () -> Void) {
        self.glyph = glyph; self.label = label; self.size = size; self.action = action
    }
    public var body: some View {
        Button(action: action) { PixelIcon(glyph, size: size == .small ? 12 : 16) }
            .buttonStyle(.block(.secondary, size: size, fullWidth: false))
            .accessibilityLabel(label)
    }
}
