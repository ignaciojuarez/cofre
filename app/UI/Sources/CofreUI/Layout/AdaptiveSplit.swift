#if canImport(UIKit)
    import SwiftUI

    // §3.2 AdaptiveSplit: primary (min width) + secondary (fixed width) side by side when both fit,
    // else a fallback: `.stack` (VStack, same children via AnyLayout), `.segmented` (one pane at a time) or `.panes`
    // (one picker over the primary and the secondary's views).

    public struct AdaptiveSplit<P: View, S: View>: View {
        public enum Fallback {
            case stack
            case segmented(LocalizedStringKey, LocalizedStringKey)
            /// One picker for the primary (index 0) and every view of the secondary (1…); the secondary reads the
            /// selection to pick its view.
            case panes([LocalizedStringKey])
        }

        let primaryMin: CGFloat, secondaryWidth: CGFloat, fallback: Fallback
        let primary: P, secondary: S
        var pick: Binding<Int>?

        @Environment(\.widthClass) private var widthClass
        @State private var ownWidth: CGFloat = 0
        @State private var localPick = 0

        public init(
            primaryMin: CGFloat = 480, secondaryWidth: CGFloat = 380, fallback: Fallback = .stack,
            @ViewBuilder primary: () -> P, @ViewBuilder secondary: () -> S
        ) {
            self.primaryMin = primaryMin
            self.secondaryWidth = secondaryWidth
            self.fallback = fallback
            self.primary = primary()
            self.secondary = secondary()
        }

        /// Keeps the segmented choice in a model (NavModel.playPane) instead of view state.
        public func selection(_ binding: Binding<Int>) -> Self {
            var c = self
            c.pick = binding
            return c
        }

        private var paneOptions: [(Int, LocalizedStringKey)] {
            switch fallback {
            case .segmented(let a, let b): [(0, a), (1, b)]
            case .panes(let labels): labels.enumerated().map { ($0.offset, $0.element) }
            case .stack: []
            }
        }

        public var body: some View {
            let fits = widthClass != .compact && ownWidth >= primaryMin + secondaryWidth
            Group {
                switch (fits, fallback) {
                case (false, .segmented), (false, .panes):
                    let sel = pick ?? $localPick
                    let picker = AnyView(Segmented("Pane", selection: sel, options: paneOptions))
                    Group {
                        if sel.wrappedValue == 0 { primary } else { secondary }
                    }
                    .environment(\.columnHeaderAccessory, picker)
                    .environment(\.widthClass, .compact)
                default:
                    let layout = fits ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                    layout {
                        primary.frame(maxWidth: .infinity, maxHeight: fits ? .infinity : nil, alignment: .top)
                        secondary
                            .frame(width: fits ? secondaryWidth : nil)
                            .frame(maxWidth: fits ? nil : .infinity, maxHeight: fits ? .infinity : nil, alignment: .top)
                            .background(fits ? Color.cofre.side.opacity(0.55) : Color.clear)
                            .overlay(alignment: .leading) { if fits { Color.cofre.outline.frame(width: 2) } }
                    }
                    .environment(\.widthClass, fits ? widthClass : .compact)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                ownWidth = $0
            }
        }
    }
#endif
