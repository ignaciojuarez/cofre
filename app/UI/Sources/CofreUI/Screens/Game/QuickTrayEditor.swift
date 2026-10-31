import SwiftUI

/// Settings editor for the six user slots. It intentionally uses the same small block controls as ControlsPane.
public struct QuickTrayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tray = QuickTraySettings.load()
    @State private var selected = 0
    @State private var editing: QuickTrayAction?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Quick menu").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                    Spacer()
                    BlockButton("Done", role: .primary, size: .small) {
                        tray.save()
                        dismiss()
                    }
                }
                preview
                HStack(spacing: 6) {
                    BlockButton("◀ Move", size: .small) {
                        tray.move(from: selected, by: -1)
                        tray.save()
                    }
                    BlockButton("Move ▶", size: .small) {
                        tray.move(from: selected, by: 1)
                        tray.save()
                    }
                    BlockButton("Remove", role: .ghostDestructive, size: .small) {
                        tray.remove(at: selected)
                        tray.save()
                    }
                }
                catalog("Common", QuickTrayCatalog.common)
                catalog("Debug", QuickTrayCatalog.debug)
                ListSection("Custom keys", spacing: 4) {
                    ForEach(tray.custom) { action in
                        let added = tray.slots.contains { $0?.id == action.id }
                        HStack {
                            Button {
                                editing = action
                            } label: {
                                HStack {
                                    Text(verbatim: action.label).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                                    Spacer()
                                    Text(verbatim: "\(action.keyHint) · \(action.mode.rawValue.capitalized)")
                                        .cofreFont(.code).foregroundStyle(Color.cofre.muted)
                                }
                            }.buttonStyle(.plain)
                            BlockButton(added ? "✓" : "+", size: .small) {
                                guard !added, let i = tray.slots.firstIndex(where: { $0 == nil }) else { return }
                                tray.slots[i] = action
                                selected = i
                                tray.save()
                            }
                        }
                        .padding(10).block(.well)
                    }
                    BlockButton("＋ New custom key", size: .small) {
                        editing = QuickTrayAction(label: "Key", keys: [.f2])
                    }
                }
                BlockButton("Reset tray", role: .ghost) {
                    tray.reset()
                    tray.save()
                }
            }
            .padding(16)
        }
        .background(Color.cofre.page)
        .sheet(item: $editing) { action in
            QuickTrayActionEditor(action: action) { saved in
                if let i = tray.custom.firstIndex(where: { $0.id == saved.id }) {
                    tray.custom[i] = saved
                } else {
                    tray.custom.append(saved)
                }
                tray.save()
                editing = nil
            }
        }
    }

    private var preview: some View {
        ListSection("Tray preview", spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                cell("Pause", glyph: .pause, fixed: true)
                ForEach(0..<6, id: \.self) { i in
                    if let action = tray.slots[i] {
                        cell(action.label, glyph: action.glyph, fixed: false, selected: selected == i) { selected = i }
                    } else {
                        cell("Empty", glyph: .keyboard, fixed: false, selected: selected == i) { selected = i }
                    }
                }
                cell("Edit", glyph: .edit, fixed: true)
            }
        }
    }

    private func cell(
        _ title: String, glyph: OverlayGlyph, fixed: Bool, selected: Bool = false, action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                OverlayButton(glyph: glyph, size: 38, on: fixed || selected)
                Text(verbatim: title).cofreFont(.caption).foregroundStyle(Color.cofre.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(3)
            .overlay { if selected { Rectangle().strokeBorder(Color.cofre.accent, lineWidth: 2) } }
        }.buttonStyle(.plain)
    }

    private func catalog(_ title: String, _ actions: [QuickTrayAction]) -> some View {
        ListSection(title, spacing: 4) {
            ForEach(actions) { action in
                let added = tray.slots.contains { $0?.id == action.id }
                HStack {
                    Text(verbatim: action.label).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Text(verbatim: action.keyHint).cofreFont(.code).foregroundStyle(Color.cofre.muted)
                    Spacer()
                    BlockButton(added ? "✓" : "+", size: .small) {
                        guard !added, let i = tray.slots.firstIndex(where: { $0 == nil }) else { return }
                        tray.slots[i] = action
                        selected = i
                        tray.save()
                    }
                }
                .padding(8).block(.well)
            }
        }
    }
}

private struct QuickTrayActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var action: QuickTrayAction
    let save: (QuickTrayAction) -> Void

    init(action: QuickTrayAction, save: @escaping (QuickTrayAction) -> Void) {
        _action = State(initialValue: action)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Custom key").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                Spacer()
                BlockButton("Save", role: .primary, size: .small) {
                    action.label = String(action.label.prefix(8))
                    action.keys = Array(action.keys.prefix(3))
                    save(action)
                    dismiss()
                }
            }
            Field("Label", text: $action.label, prompt: "Up to 8 characters")
            ForEach(action.keys.indices, id: \.self) { index in
                HStack {
                    Picker(
                        "Key \(index + 1)",
                        selection: Binding(
                            get: { action.keys[index] }, set: { action.keys[index] = $0 })
                    ) {
                        ForEach(CofreInputKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if action.keys.count > 1 {
                        BlockButton("−", size: .small) { action.keys.remove(at: index) }
                    }
                }
            }
            if action.keys.count < 3 {
                BlockButton("＋ Add chord key", size: .small) {
                    action.keys.append(action.keys.contains(.g) ? .f3 : .g)
                }
            }
            Picker("Behaviour", selection: $action.mode) {
                ForEach(QuickTrayMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Add up to two more keys in the saved chord by editing this key again.")
                .cofreFont(.caption).foregroundStyle(Color.cofre.muted)
            Spacer()
        }
        .padding(18)
        .background(Color.cofre.page)
    }
}
