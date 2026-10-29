import SwiftUI

// §2 #5 ListSection: a mono label plus a 4–5 pt stack. Long data lists use `List` (see BlockList).

public struct ListSection<Content: View>: View {
    let label: Text?, spacing: CGFloat, content: Content

    public init(_ label: LocalizedStringKey? = nil, spacing: CGFloat = 5, @ViewBuilder content: () -> Content) {
        self.label = label.map { Text($0) }
        self.spacing = spacing
        self.content = content()
    }

    @_disfavoredOverload
    public init(_ label: String, spacing: CGFloat = 5, @ViewBuilder content: () -> Content) {
        self.label = Text(verbatim: label)
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { SectionLabel(label) }
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}

/// Mono uppercase section label. Gets the header trait.
public struct SectionLabel: View {
    let text: Text
    public init(_ text: Text) { self.text = text }
    public init(_ key: LocalizedStringKey) { text = Text(key) }
    public var body: some View {
        text.cofreFont(.label).foregroundStyle(Color.cofre.muted)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Mono uppercase trailing meta ("2 h", "24 ms").
public struct Meta: View {
    let text: Text, tone: Tone?
    public init(_ text: LocalizedStringKey, tone: Tone? = nil) {
        self.text = Text(text)
        self.tone = tone
    }
    @_disfavoredOverload public init(_ text: String, tone: Tone? = nil) {
        self.text = Text(verbatim: text)
        self.tone = tone
    }
    public var body: some View {
        text.cofreFont(.label).lineLimit(1).fixedSize()
            .foregroundStyle(tone.map { Color.cofre.tone($0) } ?? Color.cofre.muted)
    }
}

/// `List` styled for blocks: plain, no separators, transparent, 5 pt gaps. Gives swipe actions,
/// keyboard selection and laziness for long data lists (§5.1).
public struct BlockList<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        List { content }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
    }
}

extension View {
    /// Row chrome inside `BlockList`.
    public func blockListRow(horizontal: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: 2.5, leading: horizontal, bottom: 2.5, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
