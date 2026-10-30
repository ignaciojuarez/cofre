#if canImport(UIKit)
import SwiftUI

/// The Cofre-owned download inbox. The queue can replace the sample items as soon as it is available;
/// keeping the view independent means Play never owns download lifecycle.
@Observable @MainActor
final class DownloadsModel {
    struct Item: Identifiable { let id: UUID; var title: String; var detail: String; var progress: Double?; var state: State }
    enum State { case running, waitingWiFi, failed(String), paused }
    var items: [Item] = [
        Item(id: UUID(), title: "Fabulously Optimized", detail: "87 of 142 mods · 212 of 341 MB", progress: 0.62, state: .running),
        Item(id: UUID(), title: "Minecraft 26.3", detail: "Waits for Wi‑Fi · 412 MB", progress: nil, state: .waitingWiFi),
    ]
    var cellular = false
    var pauseInLowPower = true
    var activeCount: Int { items.filter { if case .running = $0.state { return true }; return false }.count }
    var overall: Double {
        let values = items.compactMap(\.progress)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    func resume(_ id: UUID) { guard let i = items.firstIndex(where: { $0.id == id }) else { return }; items[i].state = .running }
    func retry(_ id: UUID) { resume(id) }
    func cancel(_ id: UUID) { items.removeAll { $0.id == id } }
}

struct CofreDownloadsStrip: View {
    @Environment(NavModel.self) private var nav
    @State private var model = DownloadsModel()
    var body: some View {
        Button { nav.sheet = .downloads } label: {
            HStack(spacing: 10) {
                Spinner()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Downloading \(model.activeCount) · \(Int(model.overall * 100))%")
                            .cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                        Spacer()
                        if model.items.contains(where: { if case .failed = $0.state { return true }; return false }) { Meta("Stopped", tone: .danger) }
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

struct CofreDownloadsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = DownloadsModel()
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Downloads") { BlockButton("Pause all", size: .small) { for i in model.items.indices { model.items[i].state = .paused } }.fixedSize() }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ListSection(spacing: 4) {
                        ForEach(model.items) { item in downloadRow(item) }
                    }
                    ListSection("While downloading", spacing: 4) {
                        ToggleRow("Use cellular data", subtitle: "Big downloads wait for Wi‑Fi", isOn: $model.cellular)
                        ToggleRow("Pause in Low Power Mode", isOn: $model.pauseInLowPower)
                    }
                    GameOwnsNote("iOS can pause downloads in the background. Cofre picks up where they stopped, and checks every file before it's used.")
                }.padding(16)
            }
        }
    }
    @ViewBuilder private func downloadRow(_ item: DownloadsModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PixelIcon(.chest, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                    Text(verbatim: item.detail).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                switch item.state {
                case .running: if let p = item.progress { Meta("\(Int(p * 100))%") }
                case .waitingWiFi: Badge("Wi‑Fi")
                case .paused: BlockButton("Resume", size: .small) { model.resume(item.id) }
                case .failed: BlockButton("Retry", size: .small) { model.retry(item.id) }
                }
                Button(role: .destructive) { model.cancel(item.id) } label: { PixelIcon(.cross, size: 14) }.buttonStyle(.plain).accessibilityLabel("Cancel \(item.title)")
            }
            if let p = item.progress { ProgressView(value: p).progressViewStyle(.xp(small: true)) }
        }.padding(.horizontal, 11).padding(.vertical, 8).frame(minHeight: 44).block(.panel)
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
                PreflightLine(downloadBytes: 412 * 1024 * 1024, freeBytes: 18_400 * 1024 * 1024)
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

struct PreflightLine: View {
    let downloadBytes: Int64, freeBytes: Int64
    var body: some View {
        HStack(spacing: 10) { PixelIcon(.check, size: 14); VStack(alignment: .leading, spacing: 1) {
            Text("Downloads \(Fmt.bytes(downloadBytes) ?? "—") · needs 1.1 GB").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
            Text("\(Fmt.bytes(freeBytes) ?? "—") free · Java 25 already here · Wi‑Fi").cofreFont(.caption).foregroundStyle(Color.cofre.muted)
        }; Spacer(minLength: 0) }.padding(.horizontal, 11).padding(.vertical, 8).block(.panel)
    }
}
#endif
