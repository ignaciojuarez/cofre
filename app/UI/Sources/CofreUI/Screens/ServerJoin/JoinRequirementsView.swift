#if canImport(UIKit)
    import SwiftUI

    // Mockup 01 "Join · first visit" and 02 "Something needs you".

    // MARK: - 01 Requirements

    struct JoinRequirementsBody: View {
        let req: ServerJoinRequirementsState
        @Binding var showsMods: Bool
        let send: (ServerJoinAction) -> Void
        @Environment(\.accessibilityReduceMotion) var reduceMotion

        var body: some View {
            ListSection("Needed to join", spacing: 4) {
                Row(
                    req.loader == .vanilla
                        ? "Minecraft \(req.gameVersion)" : "\(req.loader.displayName) \(req.gameVersion)",
                    subtitle: req.loader == .vanilla
                        ? "Java \(req.javaMajorVersion)"
                        : "Mod loader \(req.loaderVersion) · Java \(req.javaMajorVersion)"
                ) {
                    PixelIcon(req.loader.glyph, size: 28)
                } trailing: {
                    Badge("Auto", tone: req.loader.tone)
                }
                .accessibilityHint(Text("Cofre installs this for you"))
                if req.requiredModCount > 0 { modsRow }
                if showsMods {
                    ForEach(req.requiredMods) { mod in
                        Row(mod.name, subtitle: mod.detail, trailing: { Meta(Fmt.bytes(mod.sizeBytes) ?? "") })
                            .padding(.leading, 12)
                    }
                }
                ForEach(requiredPacks) { item in
                    Row(item.name, subtitle: subtitle(item), leading: { PixelIcon(.paper, size: 28) })
                }
            }
            if !optional.isEmpty {
                ListSection("Optional", spacing: 4) {
                    ForEach(optional, id: \.item.id) { o in
                        OptionalItemRow(item: o.item, glyph: o.glyph, tint: o.tint) {
                            send(.setSelected(id: o.item.id, isSelected: $0))
                        }
                    }
                }
            }
            if let trust = req.trust, trust.isFirstUse { TrustNote(trust: trust) }
        }

        /// "24 mods · Sodium, Create, Lithium… · 186 MB ›". Expands in place to the full list.
        private var modsRow: some View {
            let names =
                req.requiredMods.prefix(3).map(\.name).joined(separator: ", ") + (req.requiredMods.count > 3 ? "…" : "")
            let size = req.requiredMods.isEmpty ? nil : Fmt.bytes(req.requiredMods.reduce(0) { $0 + $1.sizeBytes })
            let title =
                req.requiredModCount == 1
                ? String(localized: "1 mod") : String(localized: "\(req.requiredModCount) mods")
            return Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { showsMods.toggle() }
            } label: {
                Row(title, subtitle: names.isEmpty ? nil : names) {
                    ModStack(count: req.requiredModCount)
                } trailing: {
                    HStack(spacing: 8) {
                        if let size { Meta(size) }
                        Chevron().rotationEffect(.degrees(showsMods ? 90 : 0))
                    }
                }
            }
            .buttonStyle(RowButtonStyle())
            .disabled(req.requiredMods.isEmpty)
            .accessibilityValue(showsMods ? Text("Shown") : Text("Hidden"))
            .accessibilityHint(Text("Shows every mod"))
        }

        /// Required resource packs and shaders sit with the mods; optional ones get a switch.
        private var requiredPacks: [SelectableContentItem] {
            (req.resourcePacks + req.shaderPacks).filter(\.isRequired)
        }

        private var optional: [(item: SelectableContentItem, glyph: PixelGlyph, tint: Color?)] {
            let amethyst = PixelArtColors.oreTints["amethyst"].map { Color(hex: $0) }
            return req.resourcePacks.filter { !$0.isRequired }.map { ($0, .paper, nil) }
                + req.shaderPacks.filter { !$0.isRequired }.map { ($0, .ore, amethyst) }
                + req.optionalMods.filter { !$0.isRequired }.map { ($0, .book, nil) }
        }

        private func subtitle(_ item: SelectableContentItem) -> String {
            [item.detail, Fmt.bytes(item.sizeBytes)].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// Three overlapping mod icons and "+21". Decorative; the row's title says the count.
    private struct ModStack: View {
        let count: Int
        private static let tints = ["diamond", "gold", "redstone"].compactMap { PixelArtColors.oreTints[$0] }

        var body: some View {
            HStack(spacing: -6) {
                ForEach(Array(Self.tints.prefix(min(3, count)).enumerated()), id: \.offset) { _, tint in
                    PixelIcon(.ore, size: 22, tint: Color(hex: tint))
                        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                }
                if count > 3 { Badge("+\(count - 3)").padding(.leading, 8) }
            }
            .accessibilityHidden(true)
        }
    }

    /// An optional mod, resource pack or shader with the server's default. The whole row is the switch.
    private struct OptionalItemRow: View {
        let item: SelectableContentItem, glyph: PixelGlyph, tint: Color?
        let onChange: (Bool) -> Void

        var body: some View {
            Toggle(isOn: Binding(get: { item.isSelected }, set: onChange)) {
                HStack(spacing: 10) {
                    PixelIcon(glyph, size: 28, tint: tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: item.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                        SubtitleText(
                            text: Text(
                                verbatim: [item.detail, Fmt.bytes(item.sizeBytes)].compactMap { $0 }.joined(
                                    separator: " · ")))
                    }
                }
            }
            .toggleStyle(.block)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .frame(minHeight: 44)
            .block(.panel)
            .blockHover()
        }
    }

    /// First visit (TOFU): where the card came from and its key, short, before anything installs.
    private struct TrustNote: View {
        let trust: ServerJoinTrust
        var body: some View {
            JoinNote {
                HStack(alignment: .top, spacing: 10) {
                    PixelIcon(.key, size: 16).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        NoteText("New server. Mods are apps that run on your device, so only join servers you trust.")
                        Text(verbatim: "\(trust.origin) · key \(ServerJoinTrust.short(trust.keyFingerprint))")
                            .cofreFont(.code).foregroundStyle(Color.cofre.muted)
                            .textSelection(.enabled)
                            .accessibilityLabel(
                                Text("Signed by \(trust.origin), key \(ServerJoinTrust.short(trust.keyFingerprint))"))
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct JoinRequirementsFooter: View {
        let req: ServerJoinRequirementsState
        let send: (ServerJoinAction) -> Void

        var body: some View {
            VStack(spacing: 8) {
                JoinPrimaryButton(title: "Install & Join", size: req.formattedDownloadSize) { send(.install) }
                Text(verbatim: fineprint).cofreFont(.code).foregroundStyle(Color.cofre.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }

        private var fineprint: String {
            let profile =
                req.isNewProfile
                ? String(localized: "Makes a new “\(req.serverName)” profile")
                : String(localized: "Updates your “\(req.serverName)” profile")
            return [profile, req.estimatedDownloadSeconds.map(joinDuration)].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: - 02 Something needs you

    struct JoinWarningsBody: View {
        let warnings: ServerJoinWarningState, req: ServerJoinRequirementsState
        let send: (ServerJoinAction) -> Void
        @Environment(\.openURL) var openURL

        private typealias ID = ServerJoinWarningState.StandardID
        private var security: [ServerJoinWarningState.WarningItem] {
            warnings.warnings.filter { $0.severity == .security }
        }
        private var incompatible: [ServerJoinWarningState.WarningItem] {
            warnings.warnings.filter { $0.severity != .security && $0.id.hasPrefix(ID.iosIncompatible) }
        }
        private var manual: [ServerJoinWarningState.WarningItem] {
            warnings.warnings.filter { $0.severity != .security && $0.id.hasPrefix(ID.curseForgeManual) }
        }
        private var others: [ServerJoinWarningState.WarningItem] {
            let grouped = Set((security + incompatible + manual).map(\.id))
            return warnings.warnings.filter { !grouped.contains($0.id) }
        }

        var body: some View {
            ForEach(security) { item in SecurityWarning(item: item, trust: req.trust, send: send) }
            if !incompatible.isEmpty {
                ListSection("Won't work on \(joinDeviceName)", spacing: 4) {
                    ForEach(incompatible) { item in
                        WarningNote(item: item, glyph: .book, iconSize: 28, tone: .warn, perform: perform)
                    }
                }
            }
            if !manual.isEmpty {
                ListSection(
                    manual.count == 1 ? "Download 1 mod yourself" : "Download \(manual.count) mods yourself", spacing: 4
                ) {
                    JoinNote(tone: .accent) {
                        NoteText(
                            "These authors only allow downloads from CurseForge. Tap Get, then Download. Cofre picks them up automatically."
                        )
                    }
                    .accessibilityElement(children: .combine)
                    ForEach(manual) { item in ManualDownloadRow(item: item) { perform(item) } }
                }
            }
            if !others.isEmpty {
                ListSection("Before you join", spacing: 4) {
                    ForEach(others) { item in
                        WarningNote(
                            item: item, glyph: item.severity == .performance ? .bolt : .paper,
                            tone: item.severity == .notice ? .accent : .warn, perform: perform)
                    }
                }
            }
        }

        /// "Get" opens the page in Safari and tells the backend to watch for the file.
        private func perform(_ item: ServerJoinWarningState.WarningItem) {
            if let url = item.actionURL, url.scheme?.lowercased() == "https" { openURL(url) }
            send(.resolveWarning(id: item.id))
        }
    }

    /// Key changed (SPEC §5.1). Unsigned rotation: blocked, ask the owner. Signed rotation: confirm, natively.
    private struct SecurityWarning: View {
        let item: ServerJoinWarningState.WarningItem
        let trust: ServerJoinTrust?
        let send: (ServerJoinAction) -> Void
        @State private var confirming = false

        private var isUnverifiedRotation: Bool {
            item.id.hasPrefix(ServerJoinWarningState.StandardID.keyRotationUnverified)
        }

        var body: some View {
            JoinNote(tone: item.isResolved ? .success : .danger) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        PixelIcon(item.isResolved ? .check : .cross, size: 14).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            // The key-changed copy is ours, so it reads the same for every server.
                            (isUnverifiedRotation ? Text("This server's key changed") : Text(verbatim: item.title))
                                .cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).fixedSize(
                                    horizontal: false, vertical: true)
                            if isUnverifiedRotation {
                                NoteText(
                                    "Cofre can't tell if the new key is from the same owner. Someone could be pretending to be this server. Check with the owner before you join."
                                )
                            } else {
                                NoteText(verbatim: item.message)
                            }
                        }
                    }
                    if let trust, let pinned = trust.pinnedKeyFingerprint {
                        Text(
                            "Was \(ServerJoinTrust.short(pinned)) · now \(ServerJoinTrust.short(trust.keyFingerprint))"
                        )
                        .cofreFont(.code).foregroundStyle(Color.cofre.muted).padding(.leading, 24)
                    }
                    if item.isResolved {
                        Meta("New key trusted", tone: .success).padding(.leading, 24)
                    } else if let label = item.actionLabel {
                        BlockButton(label, role: .destructive, size: .small) { confirming = true }.padding(.leading, 24)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            // System-owned confirmation (§0 rule 4) before pinning a new key.
            .alert("Trust the new key?", isPresented: $confirming) {
                Button(item.actionLabel ?? String(localized: "Trust new key"), role: .destructive) {
                    send(.resolveWarning(id: item.id))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Only do this if the server owner told you the key changed. Cofre then checks updates against the new key."
                )
            }
            .onAppear {
                if !item.isResolved {
                    AccessibilityNotification.Announcement(String(localized: "Warning. This server's key changed."))
                        .post()
                }
            }
        }
    }

    /// An item that won't run here, or another warning, with an optional action.
    private struct WarningNote: View {
        let item: ServerJoinWarningState.WarningItem
        let glyph: PixelGlyph
        var iconSize: CGFloat = 14
        let tone: Tone
        let perform: (ServerJoinWarningState.WarningItem) -> Void

        var body: some View {
            JoinNote(tone: tone) {
                HStack(alignment: .top, spacing: 10) {
                    PixelIcon(glyph, size: iconSize).padding(.top, iconSize > 20 ? 0 : 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).fixedSize(
                            horizontal: false, vertical: true)
                        NoteText(verbatim: item.message, color: Color.cofre.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let label = item.actionLabel, !item.isResolved {
                        BlockButton(label, size: .small) { perform(item) }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// A CurseForge-only mod: "Get ↗" until Cofre finds the file, then a check.
    private struct ManualDownloadRow: View {
        let item: ServerJoinWarningState.WarningItem
        let get: () -> Void

        var body: some View {
            Row(item.title, subtitle: item.message) {
                PixelIcon(.book, size: 28)
            } trailing: {
                if item.isResolved {
                    PixelIcon(.check, size: 14).frame(minWidth: 44, minHeight: 30)
                } else {
                    BlockButton(
                        "\(item.actionLabel ?? String(localized: "Get")) \(joinArrow)", size: .small, action: get
                    )
                    .accessibilityLabel(
                        Text("\(item.actionLabel ?? String(localized: "Get")) \(item.title) on CurseForge"))
                }
            }
            .accessibilityValue(item.isResolved ? Text("Downloaded") : Text("Not downloaded yet"))
        }
    }

    struct JoinWarningsFooter: View {
        let warnings: ServerJoinWarningState, req: ServerJoinRequirementsState
        let send: (ServerJoinAction) -> Void
        @JoinDismiss var dismiss

        var body: some View {
            VStack(spacing: 8) {
                JoinPrimaryButton(
                    title: "Install & Join", size: req.formattedDownloadSize, status: warnings.primaryStatus,
                    enabled: warnings.canInstall
                ) { send(.install) }
                BlockButton("Not now") { dismiss() }
            }
        }
    }
#endif
