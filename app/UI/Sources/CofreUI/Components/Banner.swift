import SwiftUI

// §2 #20 Banner: warn · ok · bad · info, optional action. Errors are announced when they appear.

public struct Banner<Action: View>: View {
    let title: Text, icon: PixelGlyph, tone: Tone, action: Action
    var spoken: String?

    public init(_ title: LocalizedStringKey, icon: PixelGlyph, tone: Tone = .warn, @ViewBuilder action: () -> Action) {
        self.title = Text(title); self.icon = icon; self.tone = tone; self.action = action()
    }

    @_disfavoredOverload
    public init(_ title: String, icon: PixelGlyph, tone: Tone = .warn, @ViewBuilder action: () -> Action) {
        self.title = Text(verbatim: title); self.icon = icon; self.tone = tone; self.action = action(); spoken = title
    }

    public var body: some View {
        HStack(spacing: 10) {
            PixelIcon(icon, size: 18).accessibilityHidden(true)
            title.cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 7)
        .frame(minHeight: 44)
        .background(BlockBackground(.panel).overlay { Color.cofre.tint(tone == .neutral ? .accent : tone, amount: 0.16).padding(2) })
        .accessibilityElement(children: .combine)
        .onAppear { if tone == .danger, let spoken { AccessibilityNotification.Announcement(spoken).post() } }
    }
}

public extension Banner where Action == EmptyView {
    init(_ title: LocalizedStringKey, icon: PixelGlyph, tone: Tone = .warn) { self.init(title, icon: icon, tone: tone) { EmptyView() } }
    @_disfavoredOverload
    init(_ title: String, icon: PixelGlyph, tone: Tone = .warn) { self.init(title, icon: icon, tone: tone) { EmptyView() } }
}
