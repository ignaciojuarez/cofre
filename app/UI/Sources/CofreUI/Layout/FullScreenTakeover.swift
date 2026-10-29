#if canImport(UIKit)
import SwiftUI

// §3.2 FullScreenTakeover: hides the shell (Launch, controls editor, game). Same on every width.

public extension View {
    func fullScreenTakeover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        fullScreenCover(isPresented: isPresented) { TakeoverContent(content: content()) }
    }

    func fullScreenTakeover<Item: Identifiable, C: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C) -> some View {
        fullScreenCover(item: item) { TakeoverContent(content: content($0)) }
    }
}

struct TakeoverContent<C: View>: View {
    let content: C
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        content
            .environment(\.widthClass, sizeClass == .compact ? .compact : .medium)
            .presentationBackground(Color.cofre.page)
            .statusBarHidden(false)
    }
}
#endif
