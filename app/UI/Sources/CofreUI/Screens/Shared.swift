#if canImport(UIKit)
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
                    nav.section = .settings
                    nav.settingsPane = .accounts
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
        var tone: Tone {
            switch self {
            case .ready: .success
            case .failed, .blocked: .danger
            case .checking: .accent
            case .unknown: .neutral
            }
        }
    }

    extension InstanceSummary {
        var sizeLine: String {
            [modCount.map { "\($0) mods" }, Fmt.bytes(sizeBytes)].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// Starts a launch and shows the takeover.
    @MainActor func startLaunch(_ store: CofreStore, _ nav: NavModel, instanceID: String? = nil, rejoin: RejoinIntent? = nil) {
        store.play(instanceID, rejoin: rejoin)
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
                    // Only what the backend can do (GAP-13). Delete always asks first.
                    if store.can(.backUpWorld) {
                        Button("Back up") {
                            Task { if let url = await store.backUpWorld(w) { presentShareSheet(url) } }
                        }
                    }
                    if store.can(.deleteWorld) {
                        Button("Delete", role: .destructive) { store.pendingConfirmation = .deleteWorld(w) }
                    }
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
                                    Text(verbatim: "\(VersionLabel.clean(item.version)) → \(to)")
                                        .foregroundStyle(Color.cofre.warn)
                                } else {
                                    Text(verbatim: item.enabled ? VersionLabel.clean(item.version) : String(localized: "Off"))
                                        .foregroundStyle(Color.cofre.muted)
                                }
                            }
                            .cofreFont(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if item.issue != nil {
                            Badge("Needs dep", tone: .danger)
                        } else if item.updateTo != nil {
                            Badge("Update", tone: .warn)
                        }
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

    /// The system share sheet for a file, from anywhere (menus can't host a `ShareLink`).
    @MainActor func presentShareSheet(_ url: URL) {
        guard
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: {
                $0.activationState == .foregroundActive
            }),
            var top = scene.keyWindow?.rootViewController
        else { return }
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        top.present(sheet, animated: true)
    }

    extension Confirmation {
        var title: Text {
            switch self {
            case .deleteInstance(let i): Text("Delete \(i.name)?")
            case .deleteWorld(let w): Text("Delete \(w.name)?")
            case .removeAccount(let a): Text("Remove \(a.name)?")
            case .removeServer(let s): Text("Delete \(s.name)?")
            }
        }
        var message: Text {
            switch self {
            case .deleteInstance: Text("Worlds and mods in its folder are removed too.")
            case .deleteWorld: Text("It's removed from this device. This can't be undone.")
            case .removeAccount: Text("You can sign in again any time.")
            case .removeServer: Text("It's gone from this instance's list in game too. Other instances keep theirs.")
            }
        }
        var actionTitle: LocalizedStringKey {
            switch self {
            case .deleteInstance: "Delete instance"
            case .deleteWorld: "Delete world"
            case .removeAccount: "Remove"
            case .removeServer: "Delete"
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
    /// so this rechecks setup while it's on screen. Shared by Setup S04 and Settings X04; show it only while pairing
    /// isn't ready. Three steps with the command where it's used, then the key-file fallback.
    struct PairingGuide: View {
        @Environment(CofreStore.self) private var store
        @State private var copied = false

        var body: some View {
            VStack(spacing: 8) {
                step(1, "Plug this \(device) into a Mac")
                VStack(spacing: 12) {
                    CableArt()
                    HStack(spacing: 8) {
                        Spinner(size: 12)
                        Text("Waiting for your key…").cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft)
                    }
                }
                .padding(.vertical, 16).frame(maxWidth: .infinity).block(.well)
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        await store.backend.recheckSetup()
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    stepTitle(2, "On your Mac, open the Terminal app and run this")
                    Text(verbatim: CofreLinks.pairCommand).cofreFont(.code).foregroundStyle(Color.cofre.ink)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).block(.well)
                    HStack(spacing: 8) {
                        BlockButton(copied ? "Copied" : "Copy", icon: copied ? .check : .paper, role: .primary) {
                            UIPasteboard.general.string = CofreLinks.pairCommand
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        }
                        ShareLink(item: CofreLinks.pairCommand) { Text("Share") }.buttonStyle(.block(.secondary))
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).block(.panel)
                step(3, "Tap Trust on this \(device)")
            }
            KeyFileCard()
        }

        /// "iPhone" or "iPad". Product names, so not localized.
        private var device: String { UIDevice.current.model }

        private func step(_ n: Int, _ title: LocalizedStringKey) -> some View {
            stepTitle(n, title).padding(12).frame(maxWidth: .infinity, alignment: .leading).block(.panel)
        }

        private func stepTitle(_ n: Int, _ title: LocalizedStringKey) -> some View {
            HStack(spacing: 10) {
                RowIndex(n)
                Text(title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "I have a key file": the `.mobiledevicepairing` file the Mac command saves when it can't place the key over
    /// the cable. Says never to share it, since it's a key to the iPhone.
    struct KeyFileCard: View {
        var title: LocalizedStringKey = "I have a key file"
        @Environment(CofreStore.self) private var store
        @State private var choosing = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    choosing = true
                } label: {
                    HStack(spacing: 12) {
                        PixelIcon(.paper, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                            Text("The .mobiledevicepairing file the Mac made").cofreFont(.secondary)
                                .foregroundStyle(Color.cofre.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Chevron()
                    }
                    .padding(12).frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle()).block(.panel)
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    PixelIcon(.shield, size: 12)
                    Text("Never share this file. It's a key to your iPhone.").cofreFont(.secondary)
                        .foregroundStyle(Color.cofre.muted).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: UTType.pairingFiles + [.data]) { r in
                if let (_, data) = readPicked(r.map { [$0] }) { store.importPairing(data) }
            }
        }
    }

    /// A Mac and an iPhone joined by a cable, with a dot running from Mac to iPhone: the key on its way.
    /// Still when Reduce Motion is on.
    struct CableArt: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private static let rows = [
            "..kkkkkkkkkkkkkkkkkkkk..............kkkkkkkkk",
            "..kssssssssssssssssssk..............ksskkkssk",
            "..kssssssssssssssssssk..............ksssssssk",
            "..ksswswwwwwwwwwwssssk..............ksssssssk",
            "..kssssssssssssssssssk..............ksYYssssk",
            "..ksswswwwwwsGsssssssk..............kYssYYYYk",
            "..kssssssssssssssssssk..............ksYYssYsk",
            "..kssssssssssssssssssk..............ksssssssk",
            "..kssssssssssssssssssk..............ksssssssk",
            "..kssssssssssssssssssk..............kswwwwwsk",
            "..kssssssssssssssssssk..............ksssssssk",
            "..kkkkkkkkkkkkkkkkkkkk..............ksssssssk",
            "ggggggggggggggggggggggggcccc........kkkkkkkkk",
            ".kkkkkkkkkkkkkkkkkkkkkk....c............c....",
            "...........................cccccccccccccc....",
        ]
        /// The cable, from the Mac's side to the iPhone's port.
        private static let cable: [(x: Int, y: Int)] =
            (24...27).map { ($0, 12) } + [(27, 13)] + (27...40).map { ($0, 14) } + [(40, 13)]

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.12)) { context in
                let tick = reduceMotion ? -1 : Int(context.date.timeIntervalSinceReferenceDate / 0.12)
                PixelArt(frame(dot: tick < 0 ? nil : tick % (Self.cable.count + 6)), palette: palette, pixel: 5)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("A Mac connected to this iPhone with a cable"))
        }

        private func frame(dot: Int?) -> [String] {
            guard let dot, dot < Self.cable.count else { return Self.rows }
            var rows = Self.rows.map(Array.init)
            let p = Self.cable[dot]
            rows[p.y][p.x] = "D"
            return rows.map { String($0) }
        }

        private var palette: [Character: Color] {
            [
                "k": Color.cofre.muted, "s": Color.cofre.panel, "w": Color.cofre.accent, "g": Color.cofre.inkSoft,
                "c": Color.cofre.inkSoft, "Y": Color.cofre.warn, "G": Color.cofre.success, "D": Color.cofre.warn,
            ]
        }
    }
#endif
