import SwiftUI

// §2 #6 Segmented. A well with face-colored on-segments. VoiceOver reads it as a Picker ("1 of 3").

public struct Segmented<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(Value, LocalizedStringKey)]
    let size: ControlSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let theme = CofreTheme.standard

    public init(
        _ title: LocalizedStringKey, selection: Binding<Value>, options: [(Value, LocalizedStringKey)],
        size: ControlSize = .regular
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                SegmentButton(label: label, isOn: value == selection, small: size == .small || size == .mini) {
                    withAnimation(reduceMotion ? nil : .linear(duration: theme.motion.toggle)) { selection = value }
                }
            }
        }
        .padding(2)
        .background(Color.cofre.well)
        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2).padding(-2) }
        .padding(2)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct SegmentButton: View {
    let label: LocalizedStringKey, isOn: Bool, small: Bool, action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(label)
                .cofreFont(small ? .chip : .buttonS)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Color.cofre.onFace : Color.cofre.muted)
                .padding(.horizontal, 6)
                .padding(.bottom, 1)
                .frame(maxWidth: .infinity, minHeight: small ? 24 : 28)
                .background {
                    if isOn {
                        Color.cofre.face
                            .overlay(alignment: .top) { Color.cofre.faceBevel.frame(height: 2) }
                            .overlay(alignment: .bottom) { Color.cofre.faceLip.frame(height: 2) }
                    } else if hovering {
                        Color.cofre.hover
                    }
                }
                .contentShape(Rectangle().inset(by: small ? -10 : -8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .blockPointer()
        .blockFocusRing()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
