import SwiftUI
import UniformTypeIdentifiers

// Small pieces several panes share. Panes are written once and used on every width.

/// Check / spinner / pending / cross for a stage or step.
struct StatusMark: View {
    let state: CheckState
    var body: some View {
        switch state {
        case .ready: PixelIcon(.check, size: 14)
        case .checking: Spinner()
        case .failed, .blocked: PixelIcon(.cross, size: 12)
        case .unknown: PendingMark()
        }
    }
}

/// Account chip for column headers.
struct AccountChip: View {
    @Environment(CofreStore.self) private var store
    @Environment(NavModel.self) private var nav
    var body: some View {
        if let a = store.activeAccount {
            Button {
                nav.section = .settings; nav.settingsPane = .accounts
            } label: {
                HStack(spacing: 8) {
                    PixelIcon(.head, size: 22)
                    Text(verbatim: a.name).cofreFont(.buttonS).foregroundStyle(Color.cofre.ink).lineLimit(1)
                }
                .padding(.leading, 3).padding(.trailing, 10).padding(.vertical, 3)
                .block(.button)
                .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .blockPointer()
            .blockFocusRing()
            .accessibilityLabel(Text("Account \(a.name)"))
        }
    }
}

extension CheckState {
    var tone: Tone { switch self { case .ready: .success; case .failed, .blocked: .danger; case .checking: .accent; case .unknown: .neutral } }
}

extension InstanceSummary {
    var sizeLine: String {
        [modCount.map { "\($0) mods" }, Fmt.bytes(sizeBytes)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Starts a launch and shows the takeover.
@MainActor func startLaunch(_ store: CofreStore, _ nav: NavModel, instanceID: String? = nil) {
    store.play(instanceID)
    nav.showingLaunch = true
}

/// World rows (Worlds pane, instance detail).
struct WorldRows: View {
    let worlds: [WorldSummary]
    var playFirst = true
    @Environment(CofreStore.self) private var store
    @Environment(NavModel.self) private var nav

    var body: some View {
        ForEach(Array(worlds.enumerated()), id: \.element.id) { i, w in
            Row(w.name, subtitle: [w.mode, w.playTime].compactMap { $0 }.joined(separator: " · ")) {
                InstanceGlyph(icon: w.icon, size: 28)
            } trailing: {
                if i == 0 && playFirst {
                    BlockButton("Play", icon: .play, role: .primary, size: .small) { startLaunch(store, nav) }
                } else if let ago = Fmt.ago(w.lastPlayed) {
                    Meta(ago)
                }
            }
            .contextMenu {
                Button("Play") { startLaunch(store, nav) }
                Button("Back up") {}
                Button("Open folder") {}
                Button("Delete", role: .destructive) {}
            }
        }
    }
}

/// Installed content rows with a switch (M04, instance detail).
struct InstalledRows: View {
    let items: [InstalledItem]
    @Environment(CofreStore.self) private var store

    var body: some View {
        ForEach(items) { item in
            Toggle(isOn: Binding(get: { item.enabled }, set: { store.setEnabled($0, item: item) })) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: item.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                        Group {
                            if let issue = item.issue {
                                Text("Needs dep · \(issue)").foregroundStyle(Color.cofre.danger)
                            } else if let to = item.updateTo {
                                Text(verbatim: "\(item.version) → \(to)").foregroundStyle(Color.cofre.warn)
                            } else {
                                Text(verbatim: item.enabled ? item.version : String(localized: "Off")).foregroundStyle(Color.cofre.muted)
                            }
                        }
                        .cofreFont(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if item.issue != nil { Badge("Needs dep", tone: .danger) } else if item.updateTo != nil { Badge("Update", tone: .warn) }
                }
            }
            .toggleStyle(.block)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .frame(minHeight: 44)
            .block(.panel)
            .blockHover()
            .opacity(item.enabled ? 1 : 0.6)
            .contextMenu {
                Button(item.enabled ? "Turn off" : "Turn on") { store.setEnabled(!item.enabled, item: item) }
                if item.updateTo != nil { Button("Update") { Task { await store.updateAll() } } }
                Button("Delete", role: .destructive) { store.deleteItem(item) }
            }
        }
    }
}

/// Reads a picked file with security scope.
func readPicked(_ result: Result<[URL], Error>) -> (URL, Data)? {
    guard case .success(let urls) = result, let url = urls.first else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return (try? Data(contentsOf: url)).map { (url, $0) }
}

extension UTType {
    static let mrpack = UTType(filenameExtension: "mrpack") ?? .zip
    static let jar = UTType(filenameExtension: "jar") ?? .data
    /// Fallback files from the Mac command are `<device name>.mobiledevicepairing`. A plain `.plist` still works.
    static let pairingFile = UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? .data
    static let pairingFiles: [UTType] = [.pairingFile, .propertyList, .xmlPropertyList]
}

/// Getting the pairing key: one command on a Mac with this device plugged in. The key arrives over the cable,
/// so this rechecks setup while it's on screen. Shared by Setup S04 and Settings X04; show it only while pairing isn't ready.
struct PairingGuide: View {
    var url: URL = CofreLinks.pairing
    @Environment(CofreStore.self) private var store

    var body: some View {
        ListSection(spacing: 4) {
            Row("Plug into a Mac with a cable", leading: { RowIndex(1) })
            Row("Run one command on the Mac", leading: { RowIndex(2) })
            Row("Unlock, tap Trust, wait for Done", leading: { RowIndex(3) })
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { link; Spacer(minLength: 0); share }
            VStack(alignment: .leading, spacing: 10) { link; share }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).block(.well)
        Row("Waiting for your key…", leading: { Spinner() }, trailing: { Meta("Auto") })
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    await store.backend.recheckSetup()
                }
            }
    }

    private var link: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("The command is at").cofreFont(.label).foregroundStyle(Color.cofre.muted)
            Text(verbatim: CofreLinks.short(url)).cofreFont(.title2).foregroundStyle(Color.cofre.accent)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private var share: some View {
        ShareLink(item: url) { Text("Send to Mac") }.buttonStyle(.block(size: .small))
    }
}
