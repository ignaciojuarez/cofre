import GameController
import SwiftUI

// §2 #25 InputHint: key caps, controller glyphs and the hint strip. Hidden from VoiceOver (commands live in the menu bar).

public struct KeyCap: View {
    let key: String
    public init(_ key: String) { self.key = key }
    public var body: some View {
        Text(verbatim: key).cofreFont(.code).foregroundStyle(Color.cofre.inkSoft)
            .padding(.horizontal, 5).padding(.bottom, 1)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.cofre.well)
            .overlay(alignment: .bottom) {
                Color.cofre.lip.frame(height: 2).padding(.horizontal, 2).padding(.bottom, 2)
            }
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
    }
}

public enum ControllerButton: String, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case x = "X"
    case y = "Y"
    case lb = "LB"
    case rb = "RB"
    case menu = "≡"

    /// Glyph from the connected controller so it matches the user's hardware.
    var systemSymbol: String? {
        guard let input = GCController.current?.physicalInputProfile else { return nil }
        let name: String =
            switch self {
            case .a: GCInputButtonA
            case .b: GCInputButtonB
            case .x: GCInputButtonX
            case .y: GCInputButtonY
            case .lb: GCInputLeftShoulder
            case .rb: GCInputRightShoulder
            case .menu: GCInputButtonMenu
            }
        return input.buttons[name]?.sfSymbolsName
    }
}

public struct ControllerGlyph: View {
    let button: ControllerButton
    public init(_ button: ControllerButton) { self.button = button }
    public var body: some View {
        Group {
            if let symbol = button.systemSymbol { Image(systemName: symbol) } else { Text(verbatim: button.rawValue) }
        }
        .font(.system(size: 9.5, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .frame(minWidth: 20, minHeight: 20)
        .background(Capsule().fill(Color(hex: PixelArtColors.controllerGlyph)))
        .overlay { Capsule().strokeBorder(Color.cofre.outline, lineWidth: 2) }
    }
}

/// One shortcut hint: key caps + label.
public struct KeyHint: View {
    let keys: String, label: LocalizedStringKey
    public init(_ keys: String, _ label: LocalizedStringKey) {
        self.keys = keys
        self.label = label
    }
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.split(separator: " ").enumerated()), id: \.offset) { KeyCap(String($0.element)) }
            Text(label).cofreFont(.label).foregroundStyle(Color.cofre.muted)
        }
        .accessibilityHidden(true)
    }
}

/// Hint strip. Shows controller glyphs only while a controller is connected.
public struct HintStrip: View {
    @State private var controller = GCController.current != nil
    public init() {}
    public var body: some View {
        Group {
            if controller {
                HStack(spacing: 12) {
                    hint(.a, "Play")
                    hint(.b, "Back")
                    hint(.y, "Search")
                    HStack(spacing: 3) {
                        ControllerGlyph(.lb)
                        ControllerGlyph(.rb)
                        Text("Section")
                    }
                    hint(.menu, "Menu")
                    KeyHint("⌘1–4", "Sections")
                }
                .cofreFont(.label).foregroundStyle(Color.cofre.muted)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cofre.well)
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .accessibilityHidden(true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in controller = true }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            controller = GCController.current != nil
        }
    }

    private func hint(_ b: ControllerButton, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 3) {
            ControllerGlyph(b)
            Text(label)
        }
    }
}
