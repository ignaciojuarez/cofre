#if canImport(UIKit)
    import Foundation
    import UIKit
    import Observation
    import CofreUI
    import CofreServerJoin

extension MrpackIndex {
    init(empty: Void) { self = try! JSONDecoder().decode(Self.self, from: Data(#"{"dependencies":{},"files":[]}"#.utf8)) }
}

    @MainActor
    @Observable final class LiveServerJoinModel: NSObject, ServerJoinViewModel {
        let server: ServerSummary
        var state: ServerJoinState = .resolving
        private let request: ServerJoinRequest
        private weak var backend: CofreBackendAdapter?

        init(request: ServerJoinRequest, backend: CofreBackendAdapter) {
            self.request = request
            self.backend = backend
            self.server = ServerSummary(
                id: request.id, name: request.server, address: request.server, hasServerCard: true)
            super.init()
            Task { await resolve() }
        }

        func send(_ action: ServerJoinAction) {
            switch action {
            case .retry: Task { await resolve() }
            case .install, .update: Task { await backend?.installJoin(request: request, model: self) }
            case .resolveWarning(let id):
                Task { await backend?.confirmJoin(request: request, warningID: id, model: self) }
            case .launch: backend?.launchJoin(request: request)
            case .dismiss: break
            case .cancelInstall: break
            case .setAutoConnect, .setAutoUpdate, .setSelected: break
            }
        }

        private func resolve() async {
            guard let backend else { return }
            do {
                let result = try await backend.resolveJoin(request)
                state = .requirements(backend.requirementsState(
                    card: result.card, plan: result.plan, request: request, trust: result.trust))
            } catch {
                state = .error(
                    ServerJoinErrorState(
                        code: .signatureRejected, title: "Server card rejected", message: String(describing: error),
                        recoveryAction: .retry))
            }
        }
    }

    extension CofreBackendAdapter {
        struct JoinResolution {
            let card: ServerCard
            let plan: InstallPlan
            let trust: TrustDecision
        }
        private static let trustStore = FileTrustStore(
            url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cofre/server-trust.json"))
        private var joinCacheURL: URL {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
                "Cofre/server-cards.json")
        }

        public func serverJoin(_ request: ServerJoinRequest) -> (any ServerJoinViewModel)? {
            LiveServerJoinModel(request: request, backend: self)
        }

        func resolveJoin(_ request: ServerJoinRequest) async throws -> JoinResolution {
            let host = request.server.split(separator: ":", maxSplits: 1).first.map(String.init) ?? request.server
            let url = request.card ?? Discovery.wellKnown(host: host)
            let result = try CardDecoder.decodeEnvelope(try await URLSessionCardFetcher().fetch(url))
            let cardHosts = result.card.server.addresses.map { URLPolicy.canonicalHost($0.host) ?? $0.host }
            guard let requestedHost = URLPolicy.canonicalHost(host), cardHosts.contains(requestedHost) else {
                throw ServerJoinError.invalidDeepLink
            }
            if let requestedPort = Int(request.server.split(separator: ":", maxSplits: 1).dropFirst().first ?? "") {
                guard
                    result.card.server.addresses.contains(where: {
                        URLPolicy.canonicalHost($0.host) == requestedHost && $0.port == requestedPort
                    })
                else { throw ServerJoinError.invalidDeepLink }
            }
            if let pin = request.pin, pin != result.envelope.publicKey { throw ServerJoinError.signatureInvalid }
            let trust = await TrustVerifier.evaluate(
                card: result.card, envelope: result.envelope, store: Self.trustStore)
            let index = MrpackIndex(empty: ())
            return JoinResolution(
                card: result.card, plan: InstallPlanner.plan(card: result.card, index: index), trust: trust)
        }

        func requirementsState(
            card: ServerCard, plan: InstallPlan, request: ServerJoinRequest, trust: TrustDecision
        ) -> ServerJoinRequirementsState {
            let address = card.server.addresses.first.map { "\($0.host):\($0.port)" } ?? request.server
            let mapped = ServerJoinRequirementsState(
                serverID: card.id, serverName: card.server.name, serverAddress: address, iconURL: card.server.icon,
                gameVersion: card.game.version, loader: Loader(rawValue: card.loader.type.rawValue) ?? .vanilla,
                loaderVersion: card.loader.version, javaMajorVersion: card.game.javaVersion, packName: card.id,
                packVersion: card.pack.version, totalDownloadSizeBytes: plan.totalDownloadSize,
                formattedDownloadSize: ByteCountFormatter.string(
                    fromByteCount: plan.totalDownloadSize, countStyle: .file), requiredModCount: plan.entries.count,
                recommendedRAMMB: card.recommendedRAMMB ?? 4096,
                deviceRAMMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576), isNewProfile: true,
                trust: ServerJoinTrust(
                    origin: card.security.origin.absoluteString, keyFingerprint: trust.fingerprint,
                    pinnedKeyFingerprint: nil, isFirstUse: trust.firstVisit))
            return mapped
        }

        func installJoin(request: ServerJoinRequest, model: LiveServerJoinModel) async {
            guard case .requirements = model.state else { return }
            do {
                let resolution = try await resolveJoin(request)
                if resolution.trust.firstVisit || resolution.trust.pinnedFingerprint != nil {
                    let item = ServerJoinWarningState.WarningItem(
                        id: ServerJoinWarningState.StandardID.keyRotationUnverified + ":trust",
                        severity: resolution.trust.keyChanged ? .blocking : .security,
                        title: resolution.trust.keyChanged ? "This server's key changed" : "Trust this server",
                        message: "Confirm the signing key before installing server content.",
                        actionLabel: resolution.trust.keyChanged ? nil : "Trust server")
                    let req = requirementsState(
                        card: resolution.card, plan: resolution.plan, request: request, trust: resolution.trust)
                    model.state = .warnings(
                        ServerJoinWarningState(warnings: [item], canProceedAnyway: false), requirements: req)
                    return
                }
                try await performInstall(resolution: resolution, request: request, model: model)
            } catch {
                model.state = .error(
                    ServerJoinErrorState(
                        code: .networkTimeout, title: "Install failed", message: String(describing: error),
                        recoveryAction: .retry))
            }
        }

        func confirmJoin(request: ServerJoinRequest, warningID: String, model: LiveServerJoinModel)
            async
        {
            guard case .warnings = model.state else { return }
            do {
                let resolution = try await resolveJoin(request)
                guard !resolution.trust.keyChanged else { return }
                await TrustVerifier.confirm(
                    card: resolution.card,
                    envelope: (try CardDecoder.decodeEnvelope(
                        try await URLSessionCardFetcher().fetch(
                            request.card ?? Discovery.wellKnown(host: request.server))).envelope), store: Self.trustStore)
                try await performInstall(resolution: resolution, request: request, model: model)
            } catch {
                model.state = .error(
                    ServerJoinErrorState(
                        code: .signatureRejected, title: "Trust failed", message: String(describing: error),
                        recoveryAction: .retry))
            }
        }

        fileprivate func performInstall(
            resolution: JoinResolution, request: ServerJoinRequest, model: LiveServerJoinModel
        ) async throws {
            model.state = .installing(
                ServerJoinInstallingState(
                    title: "Downloading server pack", progressFraction: 0, formattedProgress: "Preparing…", stages: [],
                    currentStageIndex: 0, canCancel: true))
            let maxBytes = resolution.card.pack.sizeBytes ?? resolution.card.security.maxBytes
            let staged = try await URLSessionPackDownloader().download(
                resolution.card.pack.url, allowedHosts: resolution.card.security.allowedHosts, maxBytes: maxBytes,
                expectedSHA512: resolution.card.pack.sha512)
            defer { try? FileManager.default.removeItem(at: staged.fileURL) }
            let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cofre/PackHashCache")
            try await InstallEngine(cache: FileHashCache(root: cacheURL)).verify(
                fileURL: staged.fileURL, card: resolution.card)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                air.importPack(
                    staged.fileURL, profile: request.id,
                    progress: { fraction, stage in
                        Task { @MainActor in
                            model.state = .installing(
                                ServerJoinInstallingState(
                                    title: stage, progressFraction: fraction,
                                    formattedProgress: "\(Int(fraction * 100))%", stages: [], currentStageIndex: 0,
                                    canCancel: true))
                        }
                    },
                    completion: { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    })
            }
            UserDefaults.standard.set(
                true, forKey: "cofre.server-card.\(resolution.card.server.addresses.first?.host ?? request.server)")
            model.state = .ready(
                ServerJoinReadyState(
                    serverID: resolution.card.id, serverName: resolution.card.server.name,
                    serverAddress: request.server, instanceID: request.id, isJITReady: isJITEnabled))
        }

        func launchJoin(request: ServerJoinRequest) {
            Task { try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in air.addServer(request.server, name: request.server, forProfile: request.id) { e in if let e { c.resume(throwing: e) } else { c.resume() } } } }
            _ = launch(instanceID: request.id, accountID: nil)
        }
    }
#endif
