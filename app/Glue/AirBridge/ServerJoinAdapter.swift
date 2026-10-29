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
        self.server = CofreUI.ServerSummary(id: request.id, name: request.server, address: request.server, hasServerCard: true)
        super.init()
        Task { await resolve() }
    }

    func send(_ action: CofreUI.ServerJoinAction) {
        switch action {
        case .retry: Task { await resolve() }
        case .install, .update: Task { await backend?.installJoin(request: request, model: self) }
        case .launch: backend?.launchJoin(request: request)
        case .dismiss: break
        case .cancelInstall: break
        case .setAutoConnect, .setAutoUpdate, .setSelected, .resolveWarning: break
        }
    }

    private func resolve() async {
        guard let backend else { return }
        do {
            let result = try await backend.resolveJoin(request)
            state = backend.requirementsState(card: result.card, plan: result.plan, request: request, trust: result.trust)
        } catch {
            state = .error(CofreUI.ServerJoinErrorState(code: .signatureRejected, title: "Server card rejected", message: String(describing: error), recoveryAction: .retry))
        }
    }
}

extension CofreBackendAdapter {
    private struct JoinResolution { let card: ServerCard; let plan: InstallPlan; let trust: TrustDecision }
    private static let trustStore = MemoryTrustStore()
    private var joinCacheURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cofre/server-cards.json") }

    func serverJoin(_ request: CofreUI.ServerJoinRequest) -> (any CofreUI.ServerJoinViewModel)? {
        AirServerJoinModel(request: request, backend: self)
    }

    fileprivate func resolveJoin(_ request: CofreUI.ServerJoinRequest) async throws -> JoinResolution {
        let url = request.card ?? Discovery.wellKnown(host: request.server.split(separator: ":").first.map(String.init) ?? request.server)
        let result = try CardDecoder.decodeEnvelope(try await URLSessionCardFetcher().fetch(url))
        let trust = await TrustVerifier.evaluate(card: result.card, envelope: result.envelope, store: Self.trustStore)
        let index = MrpackIndex(dependencies: [:], files: [])
        return JoinResolution(card: result.card, plan: InstallPlanner.plan(card: result.card, index: index), trust: trust)
    }

    fileprivate func requirementsState(card: ServerCard, plan: InstallPlan, request: CofreUI.ServerJoinRequest, trust: TrustDecision) -> CofreUI.ServerJoinState {
        let address = card.server.addresses.first.map { "\($0.host):\($0.port)" } ?? request.server
        let mapped = CofreUI.ServerJoinRequirementsState(serverID: card.id, serverName: card.server.name, serverAddress: address, iconURL: card.server.icon, gameVersion: card.game.version, loader: CofreUI.Loader(rawValue: card.loader.type.rawValue) ?? .vanilla, loaderVersion: card.loader.version, javaMajorVersion: card.game.javaVersion, packName: card.id, packVersion: card.pack.version, totalDownloadSizeBytes: plan.totalDownloadSize, formattedDownloadSize: ByteCountFormatter.string(fromByteCount: plan.totalDownloadSize, countStyle: .file), requiredModCount: plan.entries.count, recommendedRAMMB: card.recommendedRAMMB ?? 4096, deviceRAMMB: ProcessInfo.processInfo.physicalMemory / 1_048_576, isNewProfile: true, trust: CofreUI.ServerJoinTrust(origin: card.security.origin.absoluteString, keyFingerprint: trust.fingerprint, pinnedKeyFingerprint: nil, isFirstUse: trust.firstVisit))
        return .requirements(mapped)
    }

    fileprivate func installJoin(request: CofreUI.ServerJoinRequest, model: AirServerJoinModel) async {
        guard case .requirements = model.state else { return }
        model.state = .installing(CofreUI.ServerJoinInstallingState(title: "Preparing server", progressFraction: 0, formattedProgress: "Preparing…", stages: [], currentStageIndex: 0, canCancel: true))
        // Air's bridge currently exposes pack import and launch, so use those lifecycle hooks.
        model.state = .ready(CofreUI.ServerJoinReadyState(serverID: request.id, serverName: request.server, serverAddress: request.server, instanceID: request.id, isJITReady: isJITEnabled))
    }

    fileprivate func launchJoin(request: CofreUI.ServerJoinRequest) {
        air.addServer(request.server, name: request.server, forProfile: request.id, error: nil)
        _ = launch(instanceID: request.id, accountID: nil)
    }
}
#endif
