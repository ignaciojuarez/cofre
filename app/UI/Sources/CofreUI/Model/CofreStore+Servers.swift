#if canImport(UIKit)
    import Foundation

    /// A row's live state: pinging, the reply, or no reply.
    public enum ServerPingState: Equatable, Sendable {
        case pinging, offline
        case online(ServerPing)
    }

    /// What Join on a server does (plan/servers.md §Join).
    public enum ServerPlayRoute: Equatable {
        /// Launch this instance straight into the server.
        case join(instanceID: String)
        /// It publishes a server card: the Join server sheet installs what it needs (GAP-14).
        case card(ServerJoinRequest)
        /// The active instance runs another version: offer one that fits, or a new one.
        case otherVersion(ServerVersionChoice)
    }

    public struct ServerVersionChoice: Identifiable, Hashable, Sendable {
        public var id: String { server.address }
        public var server: ServerSummary
        public var current: InstanceSummary
        public var needs: String
        /// Instances that run a version the server accepts, last played first.
        public var matches: [InstanceSummary]
    }

    /// A pasted or linked address: host, host:port or [IPv6]:port. A bare name may resolve through SRV.
    public enum ServerAddress {
        /// Trimmed, with a leading `minecraft://` or `https://` dropped. `nil` when it can't be an address.
        public static func clean(_ raw: String) -> String? {
            var a = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            for scheme in ["minecraft://", "https://", "http://"] where a.lowercased().hasPrefix(scheme) {
                a = String(a.dropFirst(scheme.count))
            }
            if a.hasSuffix("/") { a.removeLast() }
            guard !a.isEmpty, a.count <= 255, !a.contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
            if a.filter({ $0 == ":" }).count == 1, let colon = a.lastIndex(of: ":") {
                guard let port = Int(a[a.index(after: colon)...]), (1...65535).contains(port) else { return nil }
            }
            return a
        }
    }

    extension CofreStore {
        static func key(_ address: String) -> String { address.trimmingCharacters(in: .whitespaces).lowercased() }

        /// `true` until the active instance's servers.dat has loaded.
        public var serversLoading: Bool { activeInstance != nil && serversInstanceID != activeInstance?.id }

        public func pingState(_ s: ServerSummary) -> ServerPingState? { serverPings[Self.key(s.address)] }

        /// The file's fields with the last ping on top.
        public func live(_ s: ServerSummary) -> ServerSummary {
            if case .online(let p) = pingState(s) { return s.updated(with: p) }
            return s
        }

        /// Pings every server not already answered. Rows show bars, MOTD and players as replies come in.
        public func pingServers(force: Bool = false) {
            guard can(.pingServers) else { return }
            for s in servers {
                let k = Self.key(s.address)
                if !force, let state = serverPings[k], state != .offline { continue }
                serverPings[k] = .pinging
                Task {
                    do {
                        let p = try await backend.pingServer(address: s.address)
                        serverPings[k] = .online(p)
                    } catch { serverPings[k] = .offline }
                }
            }
        }

        /// Reads servers.dat again, so what changed in game shows up (on every show, and after the game closes).
        public func reloadServers() async {
            guard let id = activeInstance?.id else { return }
            await run {
                self.servers = try await self.backend.servers(instanceID: id)
                self.serversInstanceID = id
                self.pingServers()
            }
        }

        // MARK: Files

        /// Appends to `instanceID`'s servers.dat: a pasted address or a link (named after the address; rename it in
        /// game), a Recommended pick, or another instance's server (copied whole). Already there: returns that one.
        @discardableResult public func addServer(
            address raw: String, name: String? = nil, from file: ServerSummary? = nil, to instanceID: String
        ) async -> ServerSummary? {
            guard let address = ServerAddress.clean(raw) else {
                lastError = String(localized: "That isn't a server address.")
                return nil
            }
            let theirs =
                instanceID == serversInstanceID ? servers : (try? await backend.servers(instanceID: instanceID))
            if let found = theirs?.first(where: { Self.key($0.address) == Self.key(address) }) { return found }
            var added: ServerSummary?
            await run {
                if let file, file.instanceID != nil, self.can(.serverFiles) {
                    added = try await self.backend.copyServer(file, to: instanceID)
                } else {
                    added = try await self.backend.addServer(
                        instanceID: instanceID, name: name ?? address, address: address)
                }
            }
            await reloadServers()
            return added
        }

        @discardableResult public func copyServer(_ s: ServerSummary, to instanceID: String) async -> ServerSummary? {
            var copy: ServerSummary?
            await run { copy = try await self.backend.copyServer(s, to: instanceID) }
            return copy
        }

        public func removeServer(_ s: ServerSummary) async {
            await run { try await self.backend.removeServer(s) }
            await reloadServers()
        }

        // MARK: Recommended

        /// Modrinth's popular servers for the active instance, once per instance (pull to refresh asks again).
        public func loadRecommended(force: Bool = false) async {
            guard can(.discoverServers), let id = activeInstance?.id, force || recommendedInstanceID != id else {
                return
            }
            recommendedInstanceID = id
            recommendedError = nil
            recommendedLoading = true
            defer { recommendedLoading = false }
            do { recommended = try await backend.discoverServers(instanceID: id) } catch {
                recommended = []
                recommendedError = error.localizedDescription
            }
        }

        /// Recommended without what's already saved.
        public var recommendedToShow: [ServerSummary] {
            let saved = Set(servers.map { Self.key($0.address) })
            return recommended.filter { !saved.contains(Self.key($0.address)) }
        }

        // MARK: Join

        public func route(_ s: ServerSummary) -> ServerPlayRoute? {
            if s.hasServerCard && can(.serverJoin) { return .card(ServerJoinRequest(server: s.address)) }
            guard let inst = activeInstance else { return nil }
            let server = live(s)
            if case .needs(let v) = server.fit(inst) {
                let matches = instances.filter { server.gameVersions.contains($0.gameVersion) }
                    .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
                return .otherVersion(ServerVersionChoice(server: server, current: inst, needs: v, matches: matches))
            }
            return .join(instanceID: inst.id)
        }

        /// Joins with `instanceID`. A saved server is copied into that instance's servers.dat first, so it's there next
        /// time; a Recommended one is only saved by Add.
        public func join(_ s: ServerSummary, using instanceID: String) async {
            if instanceID != activeInstance?.id {
                if s.instanceID != nil { await addServer(address: s.address, name: s.name, from: s, to: instanceID) }
                await selectInstance(instanceID)
            }
            play(instanceID, server: s)
        }

        /// "New <version> instance" from the version sheet: P04 pre-filled, the server saved in it once it's made.
        public func planInstance(for c: ServerVersionChoice) {
            newInstancePlan = NewInstancePlan(name: c.server.name, version: c.needs, loader: .vanilla, server: c.server)
        }
    }
#endif
