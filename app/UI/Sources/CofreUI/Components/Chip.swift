import SwiftUI

// §2 #11 Chip / ChipGroup. Single-select group or a standalone toggle chip.

public struct Chip: View {
    let title: Text
    @Binding var isOn: Bool
    public init(_ title: LocalizedStringKey, isOn: Binding<Bool>) { self.title = Text(title); _isOn = isOn }

    public var body: some View {
        ChipFace(title: title, isOn: isOn) { isOn.toggle() }
    }
}

public struct ChipGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, LocalizedStringKey)]
    let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey = "Filter", selection: Binding<Value>, options: [(Value, LocalizedStringKey)]) {
        self.title = title; _selection = selection; self.options = options
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(options.indices, id: \.self) { i in
                    ChipFace(title: Text(options[i].1), isOn: options[i].0 == selection) { selection = options[i].0 }
                }
            }
            .padding(4)
        }
        .padding(-4)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
            }
        }
    }
}

struct ChipFace: View {
    let title: Text, isOn: Bool, action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            title.cofreFont(.chip).lineLimit(1)
                .foregroundStyle(isOn ? Color.cofre.onFace : Color.cofre.inkSoft)
                .padding(.horizontal, 9).padding(.bottom, 1)
                .frame(minHeight: 26)
                .background(BlockBackground(isOn ? .primary : .button, lip: 2))
                .overlay { if hovering { Color.cofre.hover.padding(2) } }
                .contentShape(Rectangle().inset(by: -9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .blockPointer()
        .blockFocusRing()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
