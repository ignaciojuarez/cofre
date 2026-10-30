#if canImport(UIKit)
    import SwiftUI

    // Design mock for plan/servers.md: B, worlds and servers as two sections of one scroll, to compare with A (the
    // real Worlds | Servers switch). Same rows and mock data; for the preview host only.

    public struct ServersVariationsMock: View {
        @State private var store = CofreStore(services: .mock())
        @State private var nav = NavModel()
        public init(_ variant: String = "stacked") {}

        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Worlds & servers")
                    .environment(
                        \.columnHeaderAccessory,
                        AnyView(Segmented("Pane", selection: .constant(1), options: [(0, "Play"), (1, "Worlds")])))
                PaneScroll(spacing: 5) {
                    SectionLabel("Worlds")
                    WorldRows(worlds: Array(store.worlds.prefix(3)))
                    SectionLabel(Text(verbatim: "My servers · \(store.activeInstance?.name ?? "")")).padding(.top, 14)
                    ForEach(store.servers.prefix(3)) { ServerRow(server: $0) }
                    SectionLabel("Recommended").padding(.top, 14)
                    ForEach(store.recommendedToShow.prefix(3)) { RecommendedRow(server: $0) }
                }
            }
            .environment(\.widthClass, .compact)
            .environment(store).environment(nav)
            .background { PageBackground() }
            .task {
                await store.start()
                await store.loadRecommended()
            }
        }
    }
#endif
