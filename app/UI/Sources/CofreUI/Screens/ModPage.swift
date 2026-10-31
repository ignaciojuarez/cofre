#if canImport(UIKit)
    import SwiftUI
    import CofreKit

    // M02 Mod page (plan/rich-mod-pages.md §3): header, then About · Gallery N · Versions tabs. Get is pinned so it
    // works from every tab: a bottom bar on iPhone, a 280 pt right rail on wider columns with the banners, stats,
    // Needs, links and details.

    enum ModPageTab: Hashable {
        case about, gallery, versions

        /// Gallery only when the page has images or videos.
        static func shown(_ page: ProjectPage?) -> [ModPageTab] {
            guard let page, !Gallery(page).isEmpty else { return [.about, .versions] }
            return [.about, .gallery, .versions]
        }
    }

    public struct ModPagePane: View {
        let id: String
        @Environment(CofreStore.self) private var store
        @Environment(\.widthClass) private var width
        @Environment(\.showsAllVersions) private var startAll
        @State private var tab: ModPageTab
        @State private var versionID: String?
        /// Session-only. `nil` uses the target's defaults.
        @State private var filter: VersionFilter?
        @State private var showAll = false
        @State private var ownWidth: CGFloat = 0

        public init(id: String) { self.init(id: id, tab: .about) }
        init(id: String, tab: ModPageTab) {
            self.id = id
            _tab = State(initialValue: tab)
        }

        /// The rail needs room for a readable main column beside it.
        static let railWidth: CGFloat = 280
        var hasRail: Bool { width != .compact && ownWidth >= Self.railWidth + 360 }

        public var body: some View {
            let p = store.results.first { $0.id == id }
            VStack(spacing: 0) {
                ColumnHeader(p?.title ?? "") {
                    if let url = p.flatMap({ $0.pageURL ?? $0.fallbackPageURL }) {
                        ShareLink(item: url) { Text("Share") }.buttonStyle(.block(size: .small))
                    }
                }
                if let p { page(p) } else { DetailPlaceholder() }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                ownWidth = $0
            }
            .task(id: "\(id)-\(store.modsInstance?.id ?? "")") { await store.loadProject(id) }
            .task(id: id) { await store.loadPage(id) }
            .onAppear {
                if startAll {
                    showAll = true
                    tab = .versions
                }
            }
        }

        @ViewBuilder private func page(_ p: ProjectSummary) -> some View {
            let s = ModPageState(store: store, project: p, versionID: versionID)
            let tabs = ModPageTab.shown(store.pages[id])
            let current = tabs.contains(tab) ? tab : .about
            let main = PaneScroll(readable: true) {
                ModPageHeader(project: p)
                if !hasRail {
                    ModPageStats(project: p)
                    ModPageStatus(state: s)
                }
                Segmented(
                    "Page", selection: Binding(get: { current }, set: { tab = $0 }),
                    options: tabs.map { t in
                        switch t {
                        case .about: (t, "About")
                        case .gallery: (t, "Gallery \(store.pages[id].map { Gallery($0).count } ?? 0)")
                        case .versions: (t, "Versions")
                        }
                    }
                )
                .padding(.vertical, 4)
                switch current {
                case .about: ModPageAbout(project: p, showsLinks: !hasRail)
                case .gallery: ModPageGallery(id: id)
                case .versions:
                    ModPageVersions(
                        state: s, versionID: $versionID, filter: $filter, showAll: $showAll, showsDetails: !hasRail)
                }
            }
            if hasRail {
                HStack(spacing: 0) {
                    main
                    ScrollView {
                        ModPageRail(state: s).padding(16)
                    }
                    .frame(width: Self.railWidth)
                    .background(Color.cofre.side.opacity(0.55))
                    .overlay(alignment: .leading) { Color.cofre.outline.frame(width: 2) }
                }
            } else {
                main.safeAreaInset(edge: .bottom, spacing: 0) {
                    if s.hasAction {
                        ModPageGet(state: s)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.cofre.page)
                            .overlay(alignment: .top) { Color.cofre.outline.frame(height: 2) }
                    }
                }
            }
        }
    }

    extension EnvironmentValues {
        /// Previews and screenshots: M02 opens on Versions with All versions on.
        @Entry public var showsAllVersions = false
    }

    /// What the page knows about the project's versions and install state, worked out once per render and shared
    /// by the tabs, the Get bar and the rail.
    @MainActor struct ModPageState {
        let store: CofreStore, project: ProjectSummary
        let versions: [ProjectVersion]
        /// The installed build, when it's in the list.
        let installed: String?
        /// The version a Get installs: picked by hand, else the installed one, else the preferred one.
        let chosen: String?
        let pickedByHand: Bool
        let state: ProjectInstallState

        init(store: CofreStore, project p: ProjectSummary, versionID: String?) {
            self.store = store
            project = p
            let versions = store.versions[p.id] ?? []
            self.versions = versions
            let have = store.installedItem(for: p)
            installed = have?.versionID.flatMap { v in versions.contains { $0.id == v } ? v : nil }
            chosen = versionID ?? installed ?? versions.preferred?.id
            pickedByHand = versionID != nil
            state = store.installState(p)
        }

        var id: String { project.id }
        var picked: ProjectVersion? { versions.first { $0.id == chosen } }
        var loaded: Bool { store.versions[id] != nil }
        var loading: Bool { !loaded && store.versionsError[id] == nil }
        var dependencies: [ProjectDependency] { chosen.flatMap { store.dependencies[$0] } ?? [] }
        var issue: ModCompatibilityIssue? {
            store.compatibilityIssue(id: id, name: project.title, kind: store.query.kind)
        }

        /// The pinned button's label, or nil when there's nothing to do (installed and current, or nothing fits).
        var actionTitle: String? {
            switch state {
            case .installed, .off, .update:
                if let picked, switching { return ModPagePane.title("Switch to", picked) }
                if case .update(let to) = state { return String(localized: "Update to \(to)") }
                return nil
            case .notInstalled:
                // Before the versions arrive, Get works like the results row: the store picks the build.
                guard loaded else { return String(localized: "Get") }
                guard let picked else { return nil }
                // Get takes the newest fitting release (else beta, else alpha) and says which.
                guard picked.id == versions.preferred?.id else { return ModPagePane.title("Install", picked) }
                return picked.versionChannel == .release
                    ? String(localized: "Get") : "Get · \(picked.versionChannel.label.lowercased())"
            }
        }
        var hasAction: Bool { actionTitle != nil }

        /// Another build picked by hand while one is installed: switch to it, whatever its channel.
        var switching: Bool { pickedByHand && picked != nil && picked?.id != installed }

        func act() {
            if case .update = state, !switching {
                store.update(project)
            } else {
                store.get(id, versionID: loaded ? picked?.id : nil)
            }
        }
    }

    /// The pinned Get / Update / Switch button. ⌘↩ from any tab.
    struct ModPageGet: View {
        let state: ModPageState
        var body: some View {
            if let title = state.actionTitle {
                BlockButton(title, role: .primary, isLoading: state.store.modInstalls[state.id]?.isBusy == true) {
                    state.act()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    /// Icon, title, author · source, loader chips and the compatibility badge.
    struct ModPageHeader: View {
        let project: ProjectSummary
        @Environment(CofreStore.self) private var store

        var body: some View {
            let p = project
            // Large text puts the icon above the title instead of squeezing it.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ProjectIcon(project: p, size: 64)
                    text
                }
                VStack(alignment: .leading, spacing: 10) {
                    ProjectIcon(project: p, size: 64)
                    text
                }
            }
        }

        private var text: some View {
            let p = project
            return VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: p.title).cofreFont(.title).foregroundStyle(Color.cofre.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("by \(p.author) · \(p.source.displayName)").cofreFont(.secondary)
                    .foregroundStyle(Color.cofre.muted).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { badges }
                    VStack(alignment: .leading, spacing: 4) { badges }
                }
                // Its own line: next to three loader badges it pushed the page past the screen edge.
                if let issue = store.compatibilityIssue(id: p.id, name: p.title, kind: store.query.kind) {
                    Badge(issue.badge, tone: .warn)
                }
            }
        }

        @ViewBuilder private var badges: some View {
            ForEach(project.loaders) { Badge($0.displayName, tone: $0.tone) }
            if project.clientSide { Badge("Client") }
        }
    }

    /// Downloads · fits the target · updated.
    struct ModPageStats: View {
        let project: ProjectSummary
        var minItem: CGFloat = 100
        @Environment(CofreStore.self) private var store

        var body: some View {
            let p = project
            AdaptiveGrid(minItem: minItem, maxColumns: 3) {
                Stat(Fmt.count(p.downloads), label: "Downloads")
                Stat(
                    p.fits ? "✓" : "✕", label: "Fits \(store.modsInstance?.gameVersion ?? "")",
                    tone: p.fits ? .success : .danger)
                Stat(Fmt.ago(p.updated) ?? "—", label: "Updated")
            }
        }
    }

    /// Installed / Off, why versions didn't load, and "Won't run" with its reason.
    struct ModPageStatus: View {
        let state: ModPageState

        var body: some View {
            let s = state
            let store = state.store
            let inst = store.modsInstance?.name ?? ""
            switch s.state {
            case .off:
                Banner("Off in \(inst)", icon: .check, tone: .warn) {
                    BlockButton("Turn on", size: .small, fullWidth: false) { turnOn() }
                }
            case .installed, .update:
                Banner("Installed in \(inst)", icon: .check, tone: .success)
            case .notInstalled:
                if let err = store.versionsError[s.id] {
                    Banner(String(localized: "Couldn't load versions"), icon: .cross, tone: .danger) {
                        BlockButton("Try again", size: .small, fullWidth: false) {
                            Task { await store.loadProject(s.id) }
                        }
                    }
                    Text(verbatim: err).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                }
            }
            if let issue = s.issue {
                Banner(issue.title, icon: .cross, tone: .warn)
                Text(verbatim: issue.reason).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func turnOn() {
            let store = state.store
            let p = state.project
            guard let item = store.installed[store.query.kind]?.first(where: { $0.matches(p.id, title: p.title) })
            else { return }
            store.setEnabled(true, item: item)
        }
    }

    /// What the picked version adds or offers.
    struct ModPageNeeds: View {
        let state: ModPageState
        var body: some View {
            let deps = state.dependencies
            if !deps.isEmpty {
                ListSection("Needs", spacing: 4) {
                    ForEach(deps) { d in
                        Row(
                            "\(d.required ? "Needs" : "Works with") \(d.name)",
                            subtitle: d.required ? "Dependency" : "Optional",
                            leading: { PixelIcon(.book, size: 18) },
                            trailing: {
                                Meta(
                                    d.installed ? "Installed" : d.required ? "Adds" : "Offered",
                                    tone: d.installed ? .success : d.required ? .warn : nil)
                            })
                    }
                }
            }
        }
    }

    /// The picked version's number and ID, selectable.
    struct ModPageDetails: View {
        let state: ModPageState
        var body: some View {
            if let picked = state.picked {
                ListSection("Details", spacing: 4) {
                    Row("Version", trailing: { ModPagePane.detail(picked.number) })
                    Row("ID", trailing: { ModPagePane.detail(picked.id) })
                }
            }
        }
    }

    /// iPad: everything about getting the project, beside whichever tab is open.
    struct ModPageRail: View {
        let state: ModPageState
        @Environment(CofreStore.self) private var store

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ModPageGet(state: state)
                if state.hasAction { KeyHint("⌘ ↩", "install") }
                ModPageStatus(state: state)
                ModPageStats(project: state.project, minItem: 76)
                ModPageNeeds(state: state)
                ModPageLinks(project: state.project, page: store.pages[state.id])
                ModPageDetails(state: state)
                KeyHint("esc", "back to results")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    extension ModPagePane {
        /// "Install 0.9.3 beta 1", "Switch to 0.9.2"; the channel is added when the label doesn't say it.
        static func title(_ verb: String, _ v: ProjectVersion) -> String {
            let c = v.versionChannel
            let says = c == .release || v.name.lowercased().contains(c.raw)
            return "\(verb) \(v.name)" + (says ? "" : " · \(c.label.lowercased())")
        }

        static func detail(_ value: String) -> some View {
            Text(verbatim: value).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    #if DEBUG
        #Preview("Mod page · iPhone") {
            let store = CofreStore(services: .mock())
            NavigationStack { ModPagePane(id: "sodium") }
                .environment(store)
                .environment(\.widthClass, .compact)
                .background(Color.cofre.page)
                .task { await store.search() }
        }
    #endif
#endif
