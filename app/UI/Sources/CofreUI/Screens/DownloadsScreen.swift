#if canImport(UIKit)
import CofreKit
import SwiftUI

/// Cofre's downloads, straight from CofreKit's `DownloadQueue` (one shared model for the Play strip and the sheet).
@Observable @MainActor
final class DownloadsModel {
    static let shared = DownloadsModel()
    private(set) var items: [DownloadQueue.Item] = []
    /// Downloads over 200 MB wait for Wi-Fi unless this is on.
    var cellular = UserDefaults.standard.bool(forKey: "cofre.downloads.cellular") {
        didSet {
            UserDefaults.standard.set(cellular, forKey: "cofre.downloads.cellular")
            DownloadQueue.shared.allowCellularForLargeDownloads = cellular
        }
    }

    private init() {
        DownloadQueue.shared.allowCellularForLargeDownloads = cellular
        Task { [weak self] in
            for await all in DownloadQueue.shared.updates() {
                self?.items = all.filter { ![.finished, .cancelled].contains($0.state) }.sorted { $0.title < $1.title }
            }
        }
    }

    var active: [DownloadQueue.Item] { items.filter { [.queued, .running].contains($0.state) } }
    var overall: Double {
        let sized = items.filter { $0.totalBytes != nil }
        return sized.isEmpty ? 0 : sized.map(\.fraction).reduce(0, +) / Double(sized.count)
    }
}

/// Play's strip: only while something is downloading, waiting for Wi-Fi or stopped.
struct CofreDownloadsStrip: View {
    @Environment(NavModel.self) private var nav
    private let model = DownloadsModel.shared
    var body: some View {
        if !model.items.isEmpty {
            Button { nav.sheet = .downloads } label: {
                HStack(spacing: 10) {
                    Spinner()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Downloading \(model.items.count) · \(Int(model.overall * 100))%")
                                .cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                            Spacer()
                            if model.items.contains(where: { $0.state == .failed }) { Meta("Stopped", tone: .danger) }
                        }
                        ProgressView(value: model.overall).progressViewStyle(.xp(small: true))
                        Text("Keeps going if you leave Cofre").cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                    }
                    Chevron()
                }
                .padding(.horizontal, 11).padding(.vertical, 9).block(.panel).contentShape(Rectangle())
            }.buttonStyle(RowButtonStyle())
        }
    }
}

struct CofreDownloadsSheet: View {
    @Bindable private var model = DownloadsModel.shared
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Downloads")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.items.isEmpty {
                        Text("Nothing downloading.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
                    } else {
                        ListSection(spacing: 4) { ForEach(model.items) { item in downloadRow(item) } }
                    }
                    ListSection("While downloading", spacing: 4) {
                        ToggleRow("Use cellular data", subtitle: "Otherwise downloads over 200 MB wait for Wi‑Fi", isOn: $model.cellular)
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
                    Text(verbatim: detail(item)).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                switch item.state {
                case .running, .queued: if item.totalBytes != nil { Meta("\(Int(item.fraction * 100))%") }
                case .waitingWiFi: Badge("Wi‑Fi")
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

    private func detail(_ item: DownloadQueue.Item) -> String {
        let size = item.totalBytes.flatMap { Fmt.bytes($0) }
        switch item.state {
        case .waitingWiFi: return ["Waits for Wi‑Fi", size].compactMap { $0 }.joined(separator: " · ")
        case .failed: return item.error ?? "Stopped"
        default: return [Fmt.bytes(item.completedBytes), size].compactMap { $0 }.joined(separator: " of ")
        }
    }
}

struct VersionPickerSheet: View {
    let loader: Loader?
    @Binding var selection: String
    @Environment(CofreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind = VersionKind.release
    @State private var search = ""
    @State private var versions: [GameVersion] = []
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(loader == nil ? "Minecraft version" : "\(loader!.displayName) loader")
            ScrollView { VStack(alignment: .leading, spacing: 10) {
                Field("Search", text: $search, kind: .search)
                if loader == nil { Segmented("Kind", selection: $kind, options: [(.release, "Releases"), (.snapshot, "Snapshots"), (.old, "Old")]) }
                ListSection(spacing: 4) {
                    ForEach(versions.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) }) { version in
                        Button { selection = version.id; dismiss() } label: { Row(version.id, isSelected: selection == version.id, leading: { Radio(isOn: selection == version.id) }, trailing: { Meta(version.id == selection ? "Selected" : "") }) }.buttonStyle(RowButtonStyle())
                    }
                }
                PreflightLine()
            }.padding(16) }
        }
        .task(id: "\(kind.rawValue)-\(loader?.rawValue ?? "game")") {
            if let loader {
                let values = (try? await store.backend.loaderVersions(loader: loader, game: store.activeInstance?.gameVersion ?? "1.21.1")) ?? []
                versions = values.map { GameVersion(id: $0) }
            } else {
                versions = (try? await store.backend.gameVersions(kind)) ?? []
            }
        }
    }
}

/// Free space on this device. The real download size is checked again before anything downloads (DownloadQueue).
struct PreflightLine: View {
    private var freeBytes: Int64? {
        try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
    var body: some View {
        HStack(spacing: 10) {
            PixelIcon(.check, size: 14)
            Text("\(Fmt.bytes(freeBytes) ?? "—") free on this device").cofreFont(.caption).foregroundStyle(Color.cofre.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11).padding(.vertical, 8).block(.panel)
    }
}
#endif
