#if canImport(UIKit)
    import Foundation
    import UIKit
    import Observation
    import CofreUI
    import CofreServerJoin

    @MainActor
    @Observable final class AirServerJoinModel: NSObject, ServerJoinViewModel {
        let server: CofreUI.ServerSummary
        private(set) var state: CofreUI.ServerJoinState = .resolving
        private let request: CofreUI.ServerJoinRequest
        private weak var backend: CofreBackendAdapter?

        init(request: CofreUI.ServerJoinRequest, backend: CofreBackendAdapter) {
            self.request = request
            self.backend = backend
            self.server = CofreUI.ServerSummary(
                id: request.id, name: request.server, address: request.server, hasServerCard: true)
            super.init()
            Task { await resolve() }
        }

        func send(_ action: CofreUI.ServerJoinAction) {
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
                state = backend.requirementsState(
                    card: result.card, plan: result.plan, request: request, trust: result.trust)
            } catch {
                state = .error(
                    CofreUI.ServerJoinErrorState(
                        code: .signatureRejected, title: "Server card rejected", message: String(describing: error),
                        recoveryAction: .retry))
            }
        }
    }

    extension CofreBackendAdapter {
        private struct JoinResolution {
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

        func serverJoin(_ request: CofreUI.ServerJoinRequest) -> (any CofreUI.ServerJoinViewModel)? {
            AirServerJoinModel(request: request, backend: self)
        }

        fileprivate func resolveJoin(_ request: CofreUI.ServerJoinRequest) async throws -> JoinResolution {
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
            let index = MrpackIndex(dependencies: [:], files: [])
            return JoinResolution(
                card: result.card, plan: InstallPlanner.plan(card: result.card, index: index), trust: trust)
        }

        fileprivate func requirementsState(
            card: ServerCard, plan: InstallPlan, request: CofreUI.ServerJoinRequest, trust: TrustDecision
        ) -> CofreUI.ServerJoinState {
            let address = card.server.addresses.first.map { "\($0.host):\($0.port)" } ?? request.server
            let mapped = CofreUI.ServerJoinRequirementsState(
                serverID: card.id, serverName: card.server.name, serverAddress: address, iconURL: card.server.icon,
                gameVersion: card.game.version, loader: CofreUI.Loader(rawValue: card.loader.type.rawValue) ?? .vanilla,
                loaderVersion: card.loader.version, javaMajorVersion: card.game.javaVersion, packName: card.id,
                packVersion: card.pack.version, totalDownloadSizeBytes: plan.totalDownloadSize,
                formattedDownloadSize: ByteCountFormatter.string(
                    fromByteCount: plan.totalDownloadSize, countStyle: .file), requiredModCount: plan.entries.count,
                recommendedRAMMB: card.recommendedRAMMB ?? 4096,
                deviceRAMMB: ProcessInfo.processInfo.physicalMemory / 1_048_576, isNewProfile: true,
                trust: CofreUI.ServerJoinTrust(
                    origin: card.security.origin.absoluteString, keyFingerprint: trust.fingerprint,
                    pinnedKeyFingerprint: nil, isFirstUse: trust.firstVisit))
            return .requirements(mapped)
        }

        fileprivate func installJoin(request: CofreUI.ServerJoinRequest, model: AirServerJoinModel) async {
            guard case .requirements = model.state else { return }
            do {
                let resolution = try await resolveJoin(request)
                if resolution.trust.firstVisit || resolution.trust.pinnedFingerprint != nil {
                    let item = CofreUI.ServerJoinWarningState.WarningItem(
                        id: CofreUI.ServerJoinWarningState.StandardID.keyRotationUnverified + ":trust",
                        severity: resolution.trust.keyChanged ? .blocking : .security,
                        title: resolution.trust.keyChanged ? "This server's key changed" : "Trust this server",
                        message: "Confirm the signing key before installing server content.",
                        actionLabel: resolution.trust.keyChanged ? nil : "Trust server")
                    let req = requirementsState(
                        card: resolution.card, plan: resolution.plan, request: request, trust: resolution.trust)
                    model.state = .warnings(
                        CofreUI.ServerJoinWarningState(warnings: [item], canProceedAnyway: false), requirements: req)
                    return
                }
                try await performInstall(resolution: resolution, request: request, model: model)
            } catch {
                model.state = .error(
                    CofreUI.ServerJoinErrorState(
                        code: .networkTimeout, title: "Install failed", message: String(describing: error),
                        recoveryAction: .retry))
            }
        }

        fileprivate func confirmJoin(request: CofreUI.ServerJoinRequest, warningID: String, model: AirServerJoinModel)
            async
        {
            guard case .warnings = model.state else { return }
            do {
                let resolution = try await resolveJoin(request)
                guard !resolution.trust.keyChanged else { return }
                await TrustVerifier.confirm(
                    card: resolution.card,
                    envelope: try CardDecoder.decodeEnvelope(
                        try await URLSessionCardFetcher().fetch(
                            request.card ?? Discovery.wellKnown(host: request.server))), store: Self.trustStore)
                try await performInstall(resolution: resolution, request: request, model: model)
            } catch {
                model.state = .error(
                    CofreUI.ServerJoinErrorState(
                        code: .signatureRejected, title: "Trust failed", message: String(describing: error),
                        recoveryAction: .retry))
            }
        }

        private func performInstall(
            resolution: JoinResolution, request: CofreUI.ServerJoinRequest, model: AirServerJoinModel
        ) async throws {
            model.state = .installing(
                CofreUI.ServerJoinInstallingState(
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
            try await withCheckedThrowingContinuation { continuation in
                air.importPack(
                    staged.fileURL, profile: request.id,
                    progress: { fraction, stage in
                        Task { @MainActor in
                            model.state = .installing(
                                CofreUI.ServerJoinInstallingState(
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
                CofreUI.ServerJoinReadyState(
                    serverID: resolution.card.id, serverName: resolution.card.server.name,
                    serverAddress: request.server, instanceID: request.id, isJITReady: isJITEnabled))
        }

        fileprivate func launchJoin(request: CofreUI.ServerJoinRequest) {
            air.addServer(request.server, name: request.server, forProfile: request.id, error: nil)
            _ = launch(instanceID: request.id, accountID: nil)
        }
    }
#endif
