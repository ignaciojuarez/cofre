import SwiftUI

// §3.2 ReadableColumn: full width on compact, max 720 pt centered on regular.

public struct ReadableColumn<C: View>: View {
    let maxWidth: CGFloat, content: C
    @Environment(\.widthClass) private var widthClass
    public init(maxWidth: CGFloat = 720, @ViewBuilder content: () -> C) { self.maxWidth = maxWidth; self.content = content() }
    public var body: some View {
        content
            .frame(maxWidth: maxWidth, alignment: .topLeading)
            .padding(.horizontal, widthClass == .compact ? 16 : 20)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// Standard pane: scrolling stack with the pane margins and gap (§1.3).
public struct PaneScroll<C: View>: View {
    let spacing: CGFloat, readable: Bool, content: C
    @Environment(\.widthClass) private var widthClass
    public init(spacing: CGFloat = 10, readable: Bool = false, @ViewBuilder content: () -> C) {
        self.spacing = spacing; self.readable = readable; self.content = content()
    }
    public var body: some View {
        ScrollView {
            Group {
                if readable {
                    ReadableColumn { VStack(alignment: .leading, spacing: spacing) { content } }
                } else {
                    VStack(alignment: .leading, spacing: widthClass == .compact ? min(spacing, 8) : spacing) { content }
                        .padding(.horizontal, widthClass == .compact ? 16 : 20)
                }
            }
            .padding(.top, 6).padding(.bottom, 22)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
