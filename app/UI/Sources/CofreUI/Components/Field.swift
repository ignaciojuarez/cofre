import SwiftUI

// §2 #9 Field: plain · search · secure · mono. Editing shows an accent hairline; errors get a danger outline and message.

public struct Field: View {
    public enum Kind: Sendable { case plain, search, secure, mono }

    let title: LocalizedStringKey
    @Binding var text: String
    let prompt: LocalizedStringKey?, kind: Kind, error: String?
    var trailingNote: LocalizedStringKey?

    @FocusState private var editing: Bool
    @Environment(\.isEnabled) private var enabled

    public init(_ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey? = nil, kind: Kind = .plain,
                error: String? = nil, trailingNote: LocalizedStringKey? = nil) {
        self.title = title; _text = text; self.prompt = prompt; self.kind = kind; self.error = error; self.trailingNote = trailingNote
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if kind == .search {
                    Text(verbatim: "⌕").cofreFont(.button).foregroundStyle(Color.cofre.muted).accessibilityHidden(true)
                }
                input
                    .cofreFont(kind == .mono || kind == .secure ? .code : .secondary)
                    .foregroundStyle(Color.cofre.ink)
                    .tint(Color.cofre.accent)
                    .focused($editing)
                    .accessibilityLabel(title)
                if let trailingNote { Text(trailingNote).cofreFont(.label).foregroundStyle(Color.cofre.muted) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.cofre.well)
            .overlay {
                Rectangle().strokeBorder(error != nil ? Color.cofre.danger : Color.cofre.outline, lineWidth: 2)
                    .overlay { if editing { Rectangle().strokeBorder(Color.cofre.accent, lineWidth: 1).padding(2) } }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture { editing = true }
            .opacity(enabled ? 1 : 0.42)

            if let error {
                Text(verbatim: error).cofreFont(.caption).foregroundStyle(Color.cofre.danger)
                    .onAppear { AccessibilityNotification.Announcement(error).post() }
            }
        }
    }

    @ViewBuilder private var input: some View {
        let placeholder = Text(prompt ?? title).foregroundStyle(Color.cofre.muted)
        switch kind {
        case .secure: SecureField(text: $text, prompt: placeholder) { Text(title) }
        case .mono: TextField(text: $text, prompt: placeholder, axis: .vertical) { Text(title) }
            .autocorrectionDisabled().textInputAutocapitalization(.never)
        case .search: TextField(text: $text, prompt: placeholder) { Text(title) }
            .autocorrectionDisabled().submitLabel(.search)
        case .plain: TextField(text: $text, prompt: placeholder) { Text(title) }
        }
    }
}
