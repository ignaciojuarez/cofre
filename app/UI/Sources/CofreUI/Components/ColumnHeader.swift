import SwiftUI

// §2 #26 ColumnHeader: title + trailing actions. Back button only when pushed.

public struct ColumnHeader<Trailing: View>: View {
    let title: Text, trailing: Trailing
    @Environment(\.isPushed) private var isPushed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.widthClass) private var width
    @Environment(\.columnHeaderAccessory) private var accessory

    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.trailing = trailing()
    }
    @_disfavoredOverload
    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isPushed {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: "‹").cofreFont(.header).foregroundStyle(Color.cofre.accent)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel(Text("Back"))
                }
                title.cofreFont(width == .compact ? .headerCompact : .header).foregroundStyle(Color.cofre.ink)
                    .lineLimit(1).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                HStack(spacing: 6) { trailing }
            }
            if let accessory { accessory }
        }
        .padding(.horizontal, width == .compact ? 16 : 20)
        .padding(.top, 8).padding(.bottom, 4)
        .frame(minHeight: width == .compact ? 46 : 56)
    }
}

extension ColumnHeader where Trailing == EmptyView {
    public init(_ title: LocalizedStringKey) { self.init(title) { EmptyView() } }
    @_disfavoredOverload
    public init(_ title: String) { self.init(title) { EmptyView() } }
}
