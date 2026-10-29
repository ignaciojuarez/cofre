import SwiftUI

// §2 #7 Switch. Off thumb is inkSoft so the state reads at ≥ 3:1 (§3.5 #4).

public struct BlockToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { BlockSwitch(configuration: configuration) }
}

extension ToggleStyle where Self == BlockToggleStyle { public static var block: Self { .init() } }

private struct BlockSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cofreTheme) private var theme

    var body: some View {
        let on = configuration.isOn
        Button {
            withAnimation(reduceMotion ? nil : .linear(duration: theme.motion.toggle)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                track(on: on)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : theme.block.disabledOpacity)
        .sensoryFeedback(.selection, trigger: on)
        .blockFocusRing()
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }

    private func track(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Rectangle().fill(on ? Color.cofre.face : Color.cofre.well)
            if onOffLabels {
                Text(verbatim: on ? "I" : "O").cofreFont(.chip)
                    .foregroundStyle(on ? Color.cofre.onFace : Color.cofre.muted)
                    .frame(maxWidth: .infinity, alignment: on ? .leading : .trailing).padding(.horizontal, 5)
            }
            Rectangle()
                .fill(on ? Color.white : Color.cofre.inkSoft)
                .overlay(alignment: .bottom) { (on ? Color(white: 0.79) : Color.cofre.muted).frame(height: 2) }
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .frame(width: 18, height: 18)
        }
        .frame(width: 40, height: 22)
        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
        .padding(.vertical, 11)
        .blockPointer()
    }

    private var onOffLabels: Bool {
        #if canImport(UIKit)
            UIAccessibility.isOnOffSwitchLabelsEnabled
        #else
            false
        #endif
    }
}
