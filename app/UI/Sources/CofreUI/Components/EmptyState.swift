import SwiftUI

// §2 #21 EmptyState: no instances · no results · offline · needs CF key. Title is a header; action gets first focus.

public struct EmptyState<Action: View>: View {
    let title: LocalizedStringKey, message: LocalizedStringKey, icon: PixelGlyph, action: Action
    @AccessibilityFocusState private var focused: Bool

    public init(
        _ title: LocalizedStringKey, message: LocalizedStringKey, icon: PixelGlyph, @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: 12) {
            PixelIcon(icon, size: 44).accessibilityHidden(true)
            Text(title).cofreFont(.title2).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
            Text(message).cofreFont(.secondary).foregroundStyle(Color.cofre.muted).multilineTextAlignment(.center)
            action.frame(maxWidth: 260).accessibilityFocused($focused)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }
}

extension EmptyState where Action == EmptyView {
    public init(_ title: LocalizedStringKey, message: LocalizedStringKey, icon: PixelGlyph) {
        self.init(title, message: message, icon: icon) { EmptyView() }
    }
}
