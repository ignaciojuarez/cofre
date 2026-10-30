#if canImport(UIKit)
    import SwiftUI
    import UIKit

    // §3.2 AdaptiveShell: tab bar (compact) · rail (< 1100) · sidebar (≥ 1100). Reads the window, never the device.
    // One `onGeometryChange` at the root publishes `\.widthClass`. A custom layout moves the chrome
    // from the bottom to the leading edge without rebuilding the content (keeps state).

    public struct AdaptiveShell<Content: View>: View {
        @Bindable var nav: NavModel
        let content: (NavModel.Section) -> Content
        @Environment(\.horizontalSizeClass) private var sizeClass
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let theme = CofreTheme.standard
        @State private var width: CGFloat = 0
        @State private var keyboardUp = false

        public init(nav: NavModel, @ViewBuilder content: @escaping (NavModel.Section) -> Content) {
            self.nav = nav
            self.content = content
        }

        public var body: some View {
            let widthClass = WidthClass.resolve(sizeClass: sizeClass, width: width)
            let style: NavChrome.Style =
                widthClass == .compact ? .tabBar : (widthClass == .expanded && !nav.preferRail ? .sidebar : .rail)
            ShellLayout(compact: widthClass == .compact, chromeHidden: keyboardUp) {
                content(nav.section)
                    .id(nav.section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                NavChrome(style: style, nav: nav)
            }
            .background { PageBackground() }
            .environment(\.widthClass, widthClass)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .animation(
                reduceMotion
                    ? .easeInOut(duration: theme.motion.reducedCrossfade) : .easeInOut(duration: theme.motion.column),
                value: style
            )
            // Like a native tab bar, the bottom bar stays under the keyboard instead of riding up on it.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardUp = false
            }
            .background {
                // ⌃⌘S toggles sidebar ↔ rail.
                Button("") { nav.preferRail.toggle() }.keyboardShortcut("s", modifiers: [.control, .command]).hidden()
            }
        }
    }

    /// Two subviews: content, chrome. Compact puts chrome at the bottom, regular at the leading edge.
    struct ShellLayout: Layout {
        let compact: Bool
        /// Compact only: the keyboard is up, so the content takes the whole height and the bar sits below it.
        var chromeHidden = false

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard subviews.count == 2 else { return }
            let content = subviews[0]
            let chrome = subviews[1]
            if compact {
                let h = chromeHidden ? 0 : chrome.sizeThatFits(.init(width: b.width, height: nil)).height
                chrome.place(at: CGPoint(x: b.minX, y: b.maxY - h), proposal: .init(width: b.width, height: h))
                content.place(at: b.origin, proposal: .init(width: b.width, height: b.height - h))
            } else {
                let w = chrome.sizeThatFits(.init(width: nil, height: b.height)).width
                chrome.place(at: b.origin, proposal: .init(width: w, height: b.height))
                content.place(
                    at: CGPoint(x: b.minX + w, y: b.minY), proposal: .init(width: b.width - w, height: b.height))
            }
        }
    }
#endif
