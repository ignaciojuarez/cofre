#if canImport(UIKit)
    import SwiftUI

    // Server rows (plan/servers.md): favicon · name · MOTD · version fit, Modded, players · ping bars · Join.
    // My servers (servers.dat) and Recommended (Modrinth) share the face; only the actions differ.

    /// The server's favicon: its PNG, else a block picked from the address.
    struct ServerFavicon: View {
        let server: ServerSummary, size: CGFloat
        var dimmed = false

        var body: some View {
            Group {
                if let data = server.iconPNG, let img = UIImage(data: data) {
                    Image(uiImage: img).interpolation(.none).resizable()
                } else {
                    let (glyph, tint) = Self.placeholder(server.address)
                    PixelIcon(glyph, size: size, tint: tint)
                }
            }
            .frame(width: size, height: size)
            .saturation(dimmed ? 0 : 1)
            .opacity(dimmed ? 0.6 : 1)
            .accessibilityHidden(true)
        }

        static func placeholder(_ address: String) -> (PixelGlyph, Color?) {
            let glyphs: [PixelGlyph] = [.grass, .ore, .chest, .bricks, .log, .ore, .cobble, .ore]
            let tints = PixelArtColors.oreTints.keys.sorted()
            let h = Int(InstanceIcon.stableHash(address.lowercased()))
            let glyph = glyphs[h % glyphs.count]
            let tint = PixelArtColors.oreTints[tints[(h / 7) % tints.count]]
            return (glyph, glyph == .ore ? tint.map { Color(uiColor: UIColor(hex: $0)) } : nil)
        }
    }

    /// Minecraft's five ping bars. Cycles while pinging; a cross when there's no reply.
    struct PingBars: View {
        let state: ServerPingState?
        var latency: Int?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Group {
                switch state {
                case .offline?:
                    PixelIcon(.cross, size: 10).accessibilityLabel(Text("Can't reach"))
                case .pinging?:
                    TimelineView(.periodic(from: .now, by: 0.18)) { t in
                        let lit = reduceMotion ? 0 : Int(t.date.timeIntervalSinceReferenceDate / 0.18) % 6
                        bars(lit: lit, tone: Color.cofre.muted)
                    }
                    .accessibilityLabel(Text("Pinging"))
                case .online(let p)?:
                    bars(lit: Self.level(p.latencyMS), tone: Color.cofre.success)
                        .accessibilityLabel(Text("\(p.latencyMS) ms"))
                case nil:
                    if let latency {
                        bars(lit: Self.level(latency), tone: Color.cofre.success)
                            .accessibilityLabel(Text("\(latency) ms"))
                    }
                }
            }
            .frame(minWidth: 16, alignment: .trailing)
        }

        /// Same steps as Minecraft: under 150 ms is five bars, 1 s or more is one.
        static func level(_ ms: Int) -> Int {
            switch ms {
            case ..<150: 5
            case ..<300: 4
            case ..<600: 3
            case ..<1000: 2
            default: 1
            }
        }

        private func bars(lit: Int, tone: Color) -> some View {
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(1...5, id: \.self) { i in
                    Rectangle().fill(i <= lit ? tone : Color.cofre.well)
                        .frame(width: 2.5, height: CGFloat(2 + i * 2))
                }
            }
            .padding(1.5)
            .background(Color.cofre.outline.opacity(0.35))
        }
    }

    /// "1.21.1" in green when the instance can join, "Needs 1.20.4" otherwise. Nothing when unknown.
    struct ServerFitBadge: View {
        let fit: ServerFit
        let instance: InstanceSummary?
        var body: some View {
            switch fit {
            case .fits: if let instance { Badge(instance.gameVersion, tone: .success) }
            case .needs(let v): Badge("Needs \(v)", tone: .warn)
            case .unknown: EmptyView()
            }
        }
    }

    extension ServerSummary {
        /// MOTD without `§` formatting codes, on one line.
        var plainMOTD: String? {
            guard let motd else { return nil }
            let plain = motd.replacing(#/§./#, with: "").replacing(#/\s*\n\s*/#, with: " · ")
                .trimmingCharacters(in: .whitespaces)
            return plain.isEmpty ? nil : plain
        }

        var playersLine: String? {
            guard let online = playersOnline else { return nil }
            return playersMax.map { "\(Fmt.count(online))/\(Fmt.count($0))" } ?? Fmt.count(online)
        }
    }

    /// The face both row kinds share. `trailing` is the action.
    struct ServerRowFace<Trailing: View>: View {
        let server: ServerSummary
        let ping: ServerPingState?
        let instance: InstanceSummary?
        var isModded = false
        var isSelected = false
        @ViewBuilder let trailing: Trailing
        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            let offline = ping == .offline
            HStack(spacing: 10) {
                ServerFavicon(server: server, size: 36, dimmed: offline)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(verbatim: server.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        PingBars(state: ping, latency: server.pingMS)
                    }
                    motdLine(offline: offline)
                    HStack(spacing: 4) {
                        ServerFitBadge(fit: server.fit(instance), instance: instance)
                        if isModded { Badge("Modded", tone: .accent) }
                        if let players = server.playersLine, !offline { Meta(players).padding(.leading, 2) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(minHeight: 44)
            .block(.panel, selected: isSelected)
            .blockHover()
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private func motdLine(offline: Bool) -> some View {
            let lines = typeSize.isAccessibilitySize ? 3 : 1
            if offline {
                Text("Can't reach server").cofreFont(.caption).foregroundStyle(Color.cofre.danger).lineLimit(lines)
            } else if ping == .pinging && server.plainMOTD == nil {
                Text("Pinging…").cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(lines)
            } else {
                Text(verbatim: server.plainMOTD ?? server.address).cofreFont(.caption)
                    .foregroundStyle(Color.cofre.muted).lineLimit(lines)
            }
        }
    }

    /// Join: straight in, the server card sheet, or the other-version choice.
    struct JoinServerButton: View {
        let server: ServerSummary
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        var body: some View {
            if let progress = server.hasServerCard ? store.serverJoinProgress(address: server.address) : nil {
                Meta("\(Int((progress * 100).rounded()))%")
            } else if store.can(.quickPlay) || (server.hasServerCard && store.can(.serverJoin)) {
                BlockButton("Join", role: .primary, size: .small) { playServer(server, store, nav) }
                    .accessibilityLabel(Text("Join \(server.name)"))
            }
        }
    }

    /// One entry of the instance's servers.dat. Renaming and order are the game's; Cofre joins, copies and deletes.
    struct ServerRow: View {
        let server: ServerSummary
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav

        var body: some View {
            ServerRowFace(
                server: store.live(server), ping: store.pingState(server), instance: store.activeInstance,
                isModded: server.hasServerCard && store.can(.serverJoin)
            ) {
                JoinServerButton(server: server)
            }
            .contextMenu {
                if store.can(.quickPlay) || server.hasServerCard { Button("Join") { playServer(server, store, nav) } }
                let others = store.instances.filter { $0.id != server.instanceID }
                if store.can(.serverFiles), !others.isEmpty {
                    Menu("Copy to") {
                        ForEach(others) { i in
                            Button("\(i.name) · \(i.gameVersion)") { Task { await store.copyServer(server, to: i.id) } }
                        }
                    }
                }
                Button("Copy address") { UIPasteboard.general.string = server.address }
                if store.can(.serverFiles) {
                    Button("Delete", role: .destructive) { store.pendingConfirmation = .removeServer(server) }
                }
            }
        }
    }

    /// A Modrinth pick: Add writes it to servers.dat (it then moves up to My servers); Join plays without saving.
    struct RecommendedRow: View {
        let server: ServerSummary
        @Environment(CofreStore.self) private var store
        @State private var adding = false

        var body: some View {
            ServerRowFace(
                server: server, ping: nil, instance: store.activeInstance,
                isModded: server.hasServerCard && store.can(.serverJoin)
            ) {
                HStack(spacing: 5) {
                    if store.can(.addServer), let inst = store.activeInstance {
                        BlockButton("Add", size: .small, isLoading: adding) {
                            adding = true
                            Task {
                                await store.addServer(address: server.address, name: server.name, to: inst.id)
                                adding = false
                            }
                        }
                        .accessibilityLabel(Text("Add \(server.name) to \(inst.name)"))
                    }
                    JoinServerButton(server: server)
                }
            }
            .contextMenu {
                Button("Copy address") { UIPasteboard.general.string = server.address }
            }
        }
    }

    /// Play on a server row: join, the server card sheet, or the other-version choice.
    @MainActor func playServer(_ server: ServerSummary, _ store: CofreStore, _ nav: NavModel) {
        switch store.route(server) {
        case .join(let id)?:
            store.play(id, server: store.live(server))
            nav.showingLaunch = true
        case .card(let request)?: nav.serverJoin = request
        case .otherVersion(let choice)?: nav.serverVersion = choice
        case nil: break
        }
    }
#endif
