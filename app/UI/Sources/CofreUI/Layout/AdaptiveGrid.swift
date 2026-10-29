#if canImport(UIKit)
    import SwiftUI

    // §3.2 AdaptiveGrid: as many columns as fit (capped by `maxColumns`), filling the width; one column at accessibility sizes.

    public struct AdaptiveGrid<C: View>: View {
        let minItem: CGFloat, spacing: CGFloat, maxColumns: Int, content: C
        @Environment(\.dynamicTypeSize) private var typeSize
        @State private var width: CGFloat = 0

        public init(minItem: CGFloat = 120, spacing: CGFloat = 6, maxColumns: Int = 4, @ViewBuilder content: () -> C) {
            self.minItem = minItem
            self.spacing = spacing
            self.maxColumns = maxColumns
            self.content = content()
        }

        public var body: some View {
            let min = typeSize >= .xxLarge ? minItem * 1.25 : minItem
            let fit = Int((width + spacing) / (min + spacing))
            let count = typeSize.isAccessibilitySize ? 1 : Swift.max(1, Swift.min(maxColumns, fit))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: count), spacing: spacing
            ) { content }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
        }
    }
#endif
