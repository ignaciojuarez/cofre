#if canImport(UIKit)
    import SwiftUI

    // Play's second pane: Worlds | Servers (plan/servers.md). Compact: one Play · Worlds · Servers picker.
    // Regular: Play beside this pane, with its own Worlds · Servers picker.

    struct PlaySidePane: View {
        @Environment(NavModel.self) private var nav
        @Environment(\.columnHeaderAccessory) private var splitPicker

        var body: some View {
            Group {
                if nav.playPane == 2 { ServersPane() } else { WorldsPane() }
            }
            .environment(\.columnHeaderAccessory, splitPicker ?? AnyView(sidePicker))
        }

        private var sidePicker: some View {
            Segmented(
                "Pane", selection: Binding(get: { nav.playPane == 2 ? 2 : 1 }, set: { nav.playPane = $0 }),
                options: [(1, "Worlds"), (2, "Servers")])
        }
    }

    /// My servers (the instance's servers.dat, the only saved list), then Recommended (Modrinth), clearly apart.
    /// Renaming, order and resource packs belong to the game; the list is read again whenever it shows.
    public struct ServersPane: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.scenePhase) private var scenePhase
        @State private var showAll = false
        public init() {}

        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Servers") {
                    if store.can(.addServer), let inst = store.activeInstance {
                        BlockButton("Paste", size: .small) {
                            // Read on tap only, so iOS asks about pasting just when the player wants to.
                            guard let text = UIPasteboard.general.string else {
                                store.lastError = String(localized: "Copy a server address first.")
                                return
                            }
                            Task { await store.addServer(address: text, to: inst.id) }
                        }
                        .fixedSize()
                        .accessibilityHint(Text("Adds the copied server address"))
                    }
                }
                PaneScroll(spacing: 5) {
                    mine
                    if store.can(.discoverServers) { recommended.padding(.top, 14) }
                }
                .refreshable {
                    await store.reloadServers()
                    await store.loadRecommended(force: true)
                }
            }
            .task(id: store.activeInstance?.id) { await store.loadRecommended() }
            // The game may have changed servers.dat: read it again when it closes and when Cofre comes back.
            .onChange(of: nav.showingLaunch) { _, showing in if !showing { Task { await store.reloadServers() } } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.reloadServers() } } }
        }

        @ViewBuilder private var mine: some View {
            if let inst = store.activeInstance {
                SectionLabel(Text(verbatim: "My servers · \(inst.name)"))
            }
            if store.serversLoading {
                Row("Loading servers…", leading: { Spinner() })
            } else if store.servers.isEmpty {
                EmptyState(
                    "No saved servers yet", message: "Add one from Recommended, in game, or with a cofre:// link.",
                    icon: .cmd
                )
            } else {
                if allOffline {
                    Banner("Can't reach any server. Check your connection.", icon: .cross) {
                        BlockButton("Retry", size: .small) { store.pingServers(force: true) }
                    }
                }
                ForEach(store.servers) { ServerRow(server: $0) }
            }
        }

        private var recommended: some View {
            let rows = store.recommendedToShow
            return VStack(alignment: .leading, spacing: 5) {
                SectionLabel("Recommended")
                if let inst = store.activeInstance {
                    Text("Popular on Modrinth for \(inst.loaderLabel). Cofre doesn't run or check these servers.")
                        .cofreFont(.caption).foregroundStyle(Color.cofre.muted).fixedSize(
                            horizontal: false, vertical: true
                        )
                        .padding(.bottom, 2)
                }
                if store.recommendedError != nil {
                    Banner("Can't reach Modrinth right now.", icon: .cross) {
                        BlockButton("Retry", size: .small) { Task { await store.loadRecommended(force: true) } }
                    }
                } else if store.recommendedLoading {
                    Row("Loading recommended servers…", leading: { Spinner() })
                } else if rows.isEmpty {
                    Row("Nothing new for this version right now.")
                } else {
                    ForEach(rows.prefix(showAll ? rows.count : 6)) { RecommendedRow(server: $0) }
                    if rows.count > 6 && !showAll {
                        BlockButton("Show \(rows.count - 6) more", role: .ghost) { showAll = true }
                    }
                }
            }
        }

        private var allOffline: Bool {
            store.servers.count > 1 && store.servers.allSatisfy { store.pingState($0) == .offline }
        }
    }
#endif
