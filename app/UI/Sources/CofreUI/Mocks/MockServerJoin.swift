#if canImport(UIKit)
import Observation
import UIKit

/// Join server sample data from `cofre-design/server-join/popup.html` (Ironwood SMP), scripted with `stepDelay`
/// between steps. For previews, tests and the preview host only.
@Observable @MainActor
public final class MockServerJoin: ServerJoinViewModel {
    /// Where the flow starts. The preview host and render tests pick one per screenshot.
    public enum Scenario: String, CaseIterable, Sendable {
        case resolving, firstVisit, needsAttention, keyChanged, installing, update, error, ready
    }

    public private(set) var server: ServerSummary
    public private(set) var state: ServerJoinState
    /// Every action the sheet sent, for tests.
    public private(set) var sent: [ServerJoinAction] = []

    @ObservationIgnored private let stepDelay: Double
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored var onInstalled: (() -> Void)?
    private var selection: [String: Bool] = [:]
    private var trust: ServerJoinTrust
    private var isNewProfile = true

    public init(server: ServerSummary = MockServerJoin.ironwood, scenario: Scenario = .firstVisit, stepDelay: Double = 0.35) {
        self.server = server
        self.stepDelay = stepDelay
        trust = scenario == .keyChanged ? Self.changedKey : Self.firstUseKey
        state = .resolving
        if scenario == .keyChanged { isNewProfile = false }
        switch scenario {
        case .resolving: resolve()
        case .firstVisit: state = .requirements(requirements)
        case .needsAttention: state = .warnings(Self.attention, requirements: requirements)
        case .keyChanged: state = .warnings(Self.keyChange, requirements: requirements)
        case .installing: state = .installing(Self.installingSample)
        case .update: state = .updateAvailable(Self.update)
        case .error: state = .error(Self.error)
        case .ready: state = .ready(ready)
        }
    }

    public func send(_ action: ServerJoinAction) {
        sent.append(action)
        switch action {
        case .setSelected(let id, let on):
            selection[id] = on
            if case .warnings(let w, _) = state { state = .warnings(w, requirements: requirements) } else if case .requirements = state {
                state = .requirements(requirements)
            }
        case .install:
            if case .warnings(let w, _) = state, !w.canInstall { return }
            runInstall(update: false)
        case .resolveWarning(let id):
            guard case .warnings(let w, _) = state, let item = w.warnings.first(where: { $0.id == id }) else { return }
            // Security: the user confirmed in the native alert. CurseForge: the file "arrives" a moment later.
            work = Task { [weak self] in
                if item.severity != .security { await self?.pause(4) }
                self?.markResolved(id)
            }
        case .cancelInstall:
            work?.cancel()
            state = .requirements(requirements)
        case .update: runInstall(update: true)
        case .setAutoUpdate(let on):
            if case .updateAvailable(var u) = state { u.autoUpdate = on; state = .updateAvailable(u) }
        case .setAutoConnect(let on):
            if case .ready(var r) = state { r.autoConnectOnLaunch = on; state = .ready(r) }
        case .retry: state = .resolving; resolve()
        case .launch, .dismiss: break
        }
    }

    private func pause(_ steps: Double = 1) async {
        if stepDelay > 0 { try? await Task.sleep(for: .seconds(stepDelay * steps)) } else { await Task.yield() }
    }

    private func resolve() {
        work = Task { [weak self] in
            await self?.pause(2)
            guard let self, !Task.isCancelled else { return }
            state = .requirements(requirements)
        }
    }

    private func markResolved(_ id: String) {
        guard case .warnings(let w, _) = state else { return }
        let items = w.warnings.map { item -> ServerJoinWarningState.WarningItem in
            var item = item
            if item.id == id { item.isResolved = true }
            return item
        }
        if items.first(where: { $0.id == id })?.severity == .security { trust = Self.firstUseKey.pinned(Self.changedKey.keyFingerprint) }
        state = .warnings(ServerJoinWarningState(warnings: items, canProceedAnyway: w.canProceedAnyway), requirements: requirements)
    }

    private func runInstall(update: Bool) {
        work?.cancel()
        let titles = update ? ["Create 6.0.6", "Jade", "Sophisticated Backpacks", "Check files"]
            : ["Fabric 1.21.1", "Java 21", "Mods"] + Self.optionalItems.filter { selected($0) }.map(\.name)
        let total = update ? Self.update.downloadSizeBytes : requirements.totalDownloadSizeBytes
        state = .installing(Self.installing(fraction: 0, titles: titles, total: total))
        work = Task { [weak self] in
            let ticks = 12
            for tick in 1...ticks {
                await self?.pause(0.6)
                guard let self, !Task.isCancelled else { return }
                state = .installing(Self.installing(fraction: Double(tick) / Double(ticks), titles: titles, total: total))
            }
            guard let self, !Task.isCancelled else { return }
            onInstalled?()
            state = .ready(ready)
        }
    }

    // MARK: Sample data

    nonisolated public static let ironwood = ServerSummary(id: "ironwood", name: "Ironwood SMP", address: "play.ironwood.gg",
                                               detail: "12/40 online", pingMS: 38, hasServerCard: true)
    private static let mb: Int64 = 1_048_576

    static let requiredMods: [SelectableContentItem] = [
        ("Sodium", 1), ("Create", 18), ("Lithium", 1), ("Fabric API", 2), ("Iris Shaders", 3), ("Mod Menu", 1), ("Cloth Config", 1),
        ("Architectury API", 1), ("Farmer's Delight", 5), ("Steam 'n' Rails", 2), ("FerriteCore", 1), ("Entity Culling", 1),
        ("ImmediatelyFast", 1), ("Krypton", 1), ("AppleSkin", 1), ("Jade", 1), ("Waystones", 2), ("Balm", 1), ("Supplementaries", 9),
        ("Moonlight Lib", 2), ("Lootr", 1), ("Comforts", 1), ("Terralith", 4), ("Ironwood Core", 125),
    ].map { SelectableContentItem(id: $0.0.lowercased(), name: $0.0, sizeBytes: Int64($0.1) * mb, isSelected: true, isRequired: true) }

    @MainActor static var optionalItems: [SelectableContentItem] {
        [SelectableContentItem(id: "ironwood-textures", name: "Ironwood Textures", detail: "Recommended by server", sizeBytes: 48 * mb, isSelected: true),
         SelectableContentItem(id: "complementary", name: "Complementary Shaders", detail: "Lower FPS on \(UIDevice.current.model)",
                               sizeBytes: 22 * mb, isSelected: false),
         SelectableContentItem(id: "xaero", name: "Xaero's Minimap", detail: "Only on your device", sizeBytes: 3 * mb, isSelected: true)]
    }

    private func selected(_ item: SelectableContentItem) -> Bool { selection[item.id] ?? item.isSelected }

    private var requirements: ServerJoinRequirementsState {
        let opt = Self.optionalItems.map { item -> SelectableContentItem in var i = item; i.isSelected = selected(item); return i }
        let total = Self.requiredMods.reduce(0) { $0 + $1.sizeBytes } + opt.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
        return ServerJoinRequirementsState(
            serverID: server.id, serverName: server.name, serverAddress: server.address, motd: "Survival with friends", pingMS: server.pingMS,
            gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.16.14", javaMajorVersion: 21,
            packName: "Ironwood", packVersion: "2.3", totalDownloadSizeBytes: total, formattedDownloadSize: Fmt.bytes(total) ?? "",
            estimatedDownloadSeconds: 60, requiredModCount: Self.requiredMods.count,
            optionalMods: [opt[2]], resourcePacks: [opt[0]], shaderPacks: [opt[1]],
            recommendedRAMMB: 4096, deviceRAMMB: 8192, isNewProfile: isNewProfile,
            requiredMods: Self.requiredMods, trust: trust)
    }

    static let firstUseKey = ServerJoinTrust(origin: "ironwood.gg", keyFingerprint: "7f3a9c21e4b05d18", isFirstUse: true)
    static let changedKey = ServerJoinTrust(origin: "ironwood.gg", keyFingerprint: "1b8e44d0a9f26c37",
                                            pinnedKeyFingerprint: "7f3a9c21e4b05d18", isFirstUse: false)

    private typealias Item = ServerJoinWarningState.WarningItem
    private typealias ID = ServerJoinWarningState.StandardID

    static let attention = ServerJoinWarningState(warnings: [
        Item(id: "\(ID.iosIncompatible):voicechat", severity: .notice, title: "Simple Voice Chat",
             message: "Uses desktop-only audio. The server lets you join without it. You just won't hear voice."),
        Item(id: "\(ID.curseForgeManual):steam-n-rails", severity: .blocking, title: "Steam 'n' Rails", message: "CurseForge · 2.1 MB",
             actionLabel: "Get", actionURL: URL(string: "https://www.curseforge.com/minecraft/mc-mods/create-steam-n-rails"), isResolved: true),
        Item(id: "\(ID.curseForgeManual):farmers-delight", severity: .blocking, title: "Farmer's Delight", message: "CurseForge · 4.6 MB",
             actionLabel: "Get", actionURL: URL(string: "https://www.curseforge.com/minecraft/mc-mods/farmers-delight")),
    ], canProceedAnyway: false)

    static let keyChange = ServerJoinWarningState(warnings: [
        Item(id: ID.keyRotationUnverified, severity: .security, title: "Signing key changed",
             message: "The new key isn't signed by the key you trusted before."),
    ], canProceedAnyway: false)

    static let installingSample = ServerJoinInstallingState(
        title: "Setting up your profile", progressFraction: 148.0 / 237, formattedProgress: "148 / 237 MB", speedFormatted: "4.8 MB/s",
        timeRemainingSeconds: 25, stages: [
            InstallStage(id: 0, title: "Fabric 1.21.1", state: .ready, detail: "Done"),
            InstallStage(id: 1, title: "Java 21", state: .ready, detail: "Already have"),
            InstallStage(id: 2, title: "Mods", state: .checking, detail: "17 / 24"),
            InstallStage(id: 3, title: "Ironwood Textures", state: .unknown),
            InstallStage(id: 4, title: "Xaero's Minimap", state: .unknown),
        ], currentStageIndex: 2, canCancel: true)

    static func installing(fraction f: Double, titles: [String], total: Int64) -> ServerJoinInstallingState {
        let n = Double(titles.count), current = min(Int(f * n), titles.count - 1)
        let stages = titles.enumerated().map { i, title -> InstallStage in
            let state: CheckState = f >= 1 || i < current ? .ready : i == current ? .checking : .unknown
            var detail: String? = nil
            if title == "Java 21", state == .ready { detail = "Already have" }
            if title == "Mods", state == .checking { detail = "\(Int((f * n - Double(i)) * 24)) / 24" }
            return InstallStage(id: i, title: title, state: state, detail: detail)
        }
        let done = Int64(Double(total) * f)
        return ServerJoinInstallingState(
            title: "Setting up your profile", progressFraction: f,
            formattedProgress: "\(done / mb) / \(total / mb) MB", speedFormatted: "4.8 MB/s",
            timeRemainingSeconds: f >= 1 ? nil : Int(Double(total - done) / Double(5 * mb)), stages: stages,
            currentStageIndex: current, canCancel: f < 1)
    }

    static let update = ServerJoinUpdateState(
        serverID: "ironwood", currentVersion: "2.3", newVersion: "2.4",
        addedMods: ["Sophisticated Backpacks", "Jade"], removedMods: ["Better Clouds"],
        updatedMods: [ModUpdateSummary(id: "create", name: "Create", fromVersion: "6.0.4", toVersion: "6.0.6"),
                      ModUpdateSummary(id: "lithium", name: "Lithium", fromVersion: "0.14.3", toVersion: "0.14.4"),
                      ModUpdateSummary(id: "sodium", name: "Sodium", fromVersion: "0.6.12", toVersion: "0.6.13")],
        downloadSizeBytes: 12 * mb, autoUpdate: true)

    /// Raw text on purpose: the sheet must show its own words instead.
    static let error = ServerJoinErrorState(code: .networkTimeout, title: "ERR_NET_TIMEOUT",
                                            message: "NSURLErrorDomain Code=-1001 \"The request timed out.\"", recoveryAction: .retry)

    private var ready: ServerJoinReadyState {
        ServerJoinReadyState(serverID: server.id, serverName: server.name, serverAddress: server.address, instanceID: "survival",
                             isJITReady: true, autoConnectOnLaunch: true)
    }
}

private extension ServerJoinTrust {
    func pinned(_ fingerprint: String) -> ServerJoinTrust {
        ServerJoinTrust(origin: origin, keyFingerprint: fingerprint, isFirstUse: false)
    }
}
#endif
