#if canImport(UIKit)
    import SwiftUI

    // §3.2 FullScreenTakeover: hides the shell (Launch, controls editor, game). Same on every width.

    extension View {
        public func fullScreenTakeover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C)
            -> some View
        {
            fullScreenCover(isPresented: isPresented) { TakeoverContent(content: content()) }
        }

        public func fullScreenTakeover<Item: Identifiable, C: View>(
            item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C
        ) -> some View {
            fullScreenCover(item: item) { TakeoverContent(content: content($0)) }
        }
    }

    struct TakeoverContent<C: View>: View {
        let content: C
        @Environment(\.horizontalSizeClass) private var sizeClass
        @Environment(\.sizeClasses) private var measured
        var body: some View {
            content
                .environment(\.widthClass, (measured?.horizontal ?? sizeClass) == .compact ? .compact : .medium)
                .sizeClasses(nil)
                .presentationBackground(Color.cofre.page)
                .statusBarHidden(false)
        }
    }
#endif
