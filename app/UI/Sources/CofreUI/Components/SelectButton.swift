import SwiftUI

// §2 #10 SelectButton. A block that opens a native Menu (system surface, §0 rule 4).

public struct SelectButton<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(Value, String)]
    var compact = false

    public init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [(Value, String)]) {
        self.title = title; _selection = selection; self.options = options
    }

    /// Small trailing variant for rows ("0.16.14 ▾").
    public func compactStyle() -> Self { var c = self; c.compact = true; return c }

    public var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(verbatim: options[i].1).tag(options[i].0) }
            }
        } label: {
            if compact {
                HStack(spacing: 4) { Text(verbatim: current); Text(verbatim: "▾") }
                    .cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    .frame(minHeight: 44)
            } else {
                HStack(spacing: 8) {
                    Text(verbatim: current).cofreFont(.title2).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: "▾").cofreFont(.button).foregroundStyle(Color.cofre.muted)
                }
                .foregroundStyle(Color.cofre.ink)
                .padding(.horizontal, 14).padding(.bottom, 2)
                .frame(minHeight: 50)
                .block(.button, lip: 4)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .blockPointer()
        .blockFocusRing()
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: current))
        .accessibilityHint(Text("Pop-up button"))
    }

    private var current: String { options.first { $0.0 == selection }?.1 ?? "—" }
}
