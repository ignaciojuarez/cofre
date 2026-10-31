#if canImport(UIKit)
import CofreKit
import SwiftUI

/// Cofre's downloads, straight from CofreKit's `DownloadQueue` (one shared model for the Play strip and the sheet).
@Observable @MainActor
final class DownloadsModel {
    static let shared = DownloadsModel()
    private(set) var summary = DownloadSummary([])
    private(set) var onCellular = false
    /// Big downloads the user chose to keep waiting for Wi‑Fi: the ask doesn't come back for them.
    var declined: Set<UUID> = []
    /// On cellular, downloads over 200 MB ask first unless this is on.
    var cellular = UserDefaults.standard.bool(forKey: PreferenceKey.downloadsCellular.rawValue) {
        didSet {
            UserDefaults.standard.set(cellular, forKey: PreferenceKey.downloadsCellular.rawValue)
            DownloadQueue.shared.allowCellularForLargeDownloads = cellular
        }
    }

    private init() {
        DownloadQueue.shared.allowCellularForLargeDownloads = cellular
        Task { [weak self] in
            for await all in DownloadQueue.shared.updates() {
                self?.summary = DownloadSummary(all)
                self?.onCellular = DownloadQueue.shared.isOnCellular
            }
        }
    }

    /// Big downloads waiting on cellular that the user hasn't answered yet.
    var asking: [DownloadQueue.Item] { onCellular ? summary.waitingWiFi.filter { !declined.contains($0.id) } : [] }
}

/// Play's strip: only while something is downloading, waiting for Wi‑Fi or stopped. On cellular, a big
/// download asks first instead (it never fails for it).
struct CofreDownloadsStrip: View {
    @Environment(NavModel.self) private var nav
    @Environment(CofreStore.self) private var store
    @Bindable private var model = DownloadsModel.shared
    var body: some View {
        let s = model.summary
        let asking = model.asking
        let waiting = store.waitingModInstalls
        if !asking.isEmpty {
            let bytes = asking.compactMap(\.totalBytes).reduce(0, +)
            Banner("\(Fmt.bytes(bytes) ?? "A big") download on cellular", icon: .chest) {
                BlockButton("Wait", size: .small) { model.declined.formUnion(asking.map(\.id)) }
                BlockButton("Download now", role: .primary, size: .small) {
                    NSLog("[Cofre] downloads cellular start count=%ld", asking.count)
                    asking.forEach { DownloadQueue.shared.startNow($0.id) }
                }
            }
        }
        if !s.visible.isEmpty || !waiting.isEmpty {
            Button { nav.sheet = .downloads } label: {
                HStack(spacing: 10) {
                    if s.active.isEmpty && waiting.isEmpty { PixelIcon(.chest, size: 18) } else { Spinner() }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: s.visible.isEmpty ? String(localized: "\(waiting.count) waiting") :
                                    waiting.isEmpty ? s.title : "\(s.title) · \(waiting.count) waiting")
                                .cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                            Spacer()
                            if !s.stopped.isEmpty { Meta("Stopped", tone: .danger) }
                        }
                        if !s.active.isEmpty { ProgressView(value: s.fraction).progressViewStyle(.xp(small: true)) }
                        Text(s.active.isEmpty && waiting.isEmpty ? (s.stopped.isEmpty ? "Starts on Wi‑Fi" : "Tap to resume or retry") : "Keeps going if you leave Cofre")
                            .cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                    }
                    Chevron()
                }
                .padding(.horizontal, 11).padding(.vertical, 9).block(.panel).contentShape(Rectangle())
            }.buttonStyle(RowButtonStyle())
        }
    }
}

struct CofreDownloadsSheet: View {
    @Environment(CofreStore.self) private var store
    @Bindable private var model = DownloadsModel.shared
    var body: some View {
        let waiting = store.waitingModInstalls
        VStack(spacing: 0) {
            SheetHeader("Downloads")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.summary.visible.isEmpty && waiting.isEmpty {
                        Text("Nothing downloading.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
                    } else {
                        ListSection(spacing: 4) {
                            ForEach(model.summary.visible) { item in downloadRow(item) }
                            // Gets wait their turn in Cofre before their files reach the download queue.
                            ForEach(waiting) { job in waitingRow(job) }
                        }
                    }
                    ListSection("While downloading", spacing: 4) {
                        ToggleRow("Use cellular data", subtitle: "Otherwise Cofre asks before downloads over 200 MB on cellular", isOn: $model.cellular)
                    }
                    GameOwnsNote("iOS can pause downloads in the background. Cofre picks up where they stopped, and checks every file before it's used.")
                }.padding(16)
            }
        }
    }

    @ViewBuilder private func downloadRow(_ item: DownloadQueue.Item) -> some View {
        let queue = DownloadQueue.shared
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PixelIcon(.chest, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                    Text(verbatim: detail(item)).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                switch item.state {
                case .running, .queued: if item.totalBytes != nil { Meta("\(Int(item.fraction * 100))%") }
                case .waitingWiFi: BlockButton("Download now", size: .small) { queue.startNow(item.id) }
                case .paused: BlockButton("Resume", size: .small) { queue.resume(item.id) }
                case .failed: BlockButton("Retry", size: .small) { queue.retry(item.id) }
                case .finished, .cancelled: EmptyView()
                }
                Button(role: .destructive) { queue.cancel(item.id) } label: { PixelIcon(.cross, size: 14) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel \(item.title)")
            }
            if item.totalBytes != nil, [.running, .queued].contains(item.state) {
                ProgressView(value: item.fraction).progressViewStyle(.xp(small: true))
            }
        }.padding(.horizontal, 11).padding(.vertical, 8).frame(minHeight: 44).block(.panel)
    }

    private func waitingRow(_ job: ModInstall) -> some View {
        HStack(spacing: 10) {
            PixelIcon(.chest, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: job.title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                Text("Waiting · \(store.instances.first { $0.id == job.instanceID }?.name ?? job.instanceID)")
                    .cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Meta("Next")
        }
        .padding(.horizontal, 11).padding(.vertical, 8).frame(minHeight: 44).block(.panel)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ item: DownloadQueue.Item) -> String {
        let size = item.totalBytes.flatMap { Fmt.bytes($0) }
        switch item.state {
        case .waitingWiFi: return ["Waits for Wi‑Fi", size].compactMap { $0 }.joined(separator: " · ")
        case .failed, .paused: return item.error ?? "Stopped"
        default: return [Fmt.bytes(item.completedBytes), size].compactMap { $0 }.joined(separator: " of ")
        }
    }
}

/// Minecraft versions (releases, snapshots behind a switch) or, with `loader`, that loader's versions for `game`.
struct VersionPickerSheet: View {
    let loader: Loader?
    /// When choosing a Minecraft version, annotate it for the loader selected in New Instance.
    var recommendationLoader: Loader? = nil
    /// The Minecraft version a loader list is for.
    var game: String? = nil
    @Binding var selection: String
    @Environment(CofreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots = false
    @State private var search = ""
    @State private var releases: [GameVersion] = []
    @State private var snapshotList: [GameVersion] = []
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(loader.map { "\($0.displayName) loader" } ?? "Minecraft version")
            ScrollView { VStack(alignment: .leading, spacing: 10) {
                Field("Search", text: $search, kind: .search)
                if loader == nil {
                    ToggleRow("Show snapshots", subtitle: "Test builds. They can break worlds and most mods", isOn: $snapshots)
                }
                if failed {
                    Banner("Couldn't load versions", icon: .cross, tone: .danger) {
                        BlockButton("Try again", size: .small) { attempt += 1 }
                    }
                }
                if snapshots, loader == nil { section("Snapshots", snapshotList) }
                section(loader == nil ? "Releases" : "Versions", releases)
                if loader == nil { PreflightLine(version: selection) }
            }.padding(16) }
        }
        .task(id: "\(snapshots)-\(attempt)-\(loader?.rawValue ?? "game")-\(recommendationLoader?.rawValue ?? "")-\(game ?? "")") {
            do {
                if let loader {
                    let game = game ?? store.activeInstance?.gameVersion ?? ""
                    releases = try await store.backend.loaderVersions(loader: loader, game: game).map { GameVersion(id: $0) }
                } else {
                    if releases.isEmpty { releases = try await store.backend.gameVersions(.release) }
                    if snapshots, snapshotList.isEmpty { snapshotList = try await store.backend.gameVersions(.snapshot) }
                }
                failed = false
            } catch is CancellationError { return } catch { failed = true }
        }
    }

    @ViewBuilder private func section(_ title: String, _ versions: [GameVersion]) -> some View {
        let shown = versions.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) }
        if !shown.isEmpty {
            ListSection(title, spacing: 4) {
                ForEach(shown) { version in
                    Button { selection = version.id; dismiss() } label: {
                        Row(version.id, isSelected: selection == version.id, leading: { Radio(isOn: selection == version.id) },
                            trailing: {
                                HStack(spacing: 4) {
                                    if version.id == versions.first?.id { Meta("Newest") }
                                    if let recommendationLoader, recommendationLoader != .vanilla {
                                        let recommended = RendererPolicy.isRecommendedForMods(
                                            gameVersion: version.id, loader: recommendationLoader,
                                            metalVersions: ModCompatibility.metalVersions)
                                        Badge(recommended ? "Recommended" : "Not recommended",
                                              tone: recommended ? .success : .warn)
                                    }
                                }
                            })
                    }.buttonStyle(RowButtonStyle())
                }
            }
        }
    }
}

/// The disk check before a version downloads: "Downloads 412 MB · 18.4 GB free", or a danger banner with the
/// shortfall. Launch checks again (the adapter), so this is advice, never the only gate.
struct PreflightLine: View {
    var version: String? = nil
    @Environment(CofreStore.self) private var store
    @State private var check: DiskPreflight?
    var body: some View {
        let check = check ?? DiskPreflight.check(downloadBytes: 0, at: URL(fileURLWithPath: NSHomeDirectory()))
        Group {
            if check.hasRoom {
                HStack(spacing: 10) {
                    PixelIcon(.check, size: 14)
                    Text(verbatim: check.summary).cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11).padding(.vertical, 8).block(.panel)
            } else {
                Banner(check.summary, icon: .cross, tone: .danger)
            }
        }
        .task(id: version) {
            guard let version, !version.isEmpty, let root = store.instanceStore?.root else { self.check = nil; return }
            let estimate = try? await VersionDownloads.estimate(version: version, root: root) { url in
                var request = URLRequest(url: url); request.timeoutInterval = 10
                return try await URLSession.shared.data(for: request).0
            }
            guard !Task.isCancelled else { return }
            self.check = .check(downloadBytes: estimate?.totalBytes ?? 0, at: root)
        }
    }
}
#endif
