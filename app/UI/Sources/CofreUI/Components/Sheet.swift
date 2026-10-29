import SwiftUI

// §2 #22 Sheet: form-sized and centered on regular, bottom sheet with detents on compact. Opaque panel, no glass.

extension View {
    public func blockSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        sheet(isPresented: isPresented) { BlockSheetContent(content: content()) }
    }

    public func blockSheet<Item: Identifiable, C: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        sheet(item: item) { BlockSheetContent(content: content($0)) }
    }
}

struct BlockSheetContent<C: View>: View {
    let content: C
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if canImport(UIKit)
        @Environment(\.sizeClasses) private var measured
    #endif
    @Environment(\.dismiss) private var dismiss

    private var compact: Bool {
        #if canImport(UIKit)
            return (measured?.horizontal ?? sizeClass) == .compact
        #else
            return sizeClass == .compact
        #endif
    }

    var body: some View {
        content
            .environment(\.widthClass, compact ? .compact : .medium)
            .environment(\.isPushed, false)
            .modifier(ReapplySizeClasses())
            .presentationBackground(Color.cofre.panel)
            .presentationDetents(compact ? [.medium, .large] : [.large])
            .presentationDragIndicator(compact ? .visible : .hidden)
            .modifier(FormSizing())
            .background {
                // Esc: a hidden cancel button works even when nothing in the sheet has focus.
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

/// Sheets read UIKit's size classes again; reapply the root's measured ones (see `SizeClasses`).
private struct ReapplySizeClasses: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(UIKit)
            content.sizeClasses(nil)
        #else
            content
        #endif
    }
}

private struct FormSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) { content.presentationSizing(.form) } else { content }
    }
}

/// Header for sheets: title plus a close button (Esc also closes).
public struct SheetHeader<Trailing: View>: View {
    let title: LocalizedStringKey, trailing: Trailing
    @Environment(\.dismiss) private var dismiss
    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }
    public var body: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text(verbatim: "‹").cofreFont(.header).foregroundStyle(Color.cofre.accent).frame(
                    minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Close"))
            Text(title).cofreFont(.header).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.top, 10)
    }
}

extension SheetHeader where Trailing == EmptyView {
    public init(_ title: LocalizedStringKey) { self.init(title) { EmptyView() } }
}
