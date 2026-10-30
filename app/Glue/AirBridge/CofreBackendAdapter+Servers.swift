#if canImport(UIKit)
import Foundation
import CofreKit
import CofreUI

extension CofreBackendAdapter {
    func storedInstance(_ id: String) throws -> Instance {
        guard let instance = try instances?.list().first(where: { $0.id == id }) else {
            throw InstanceStore.StoreError.missingProfile
        }
        return instance
    }
    private func serverStore(_ id: String) throws -> CofreServersStore {
        let directory = try storedInstance(id).gameDirectory.standardizedFileURL
        return CofreServersStore(gameDirectory: directory) { [weak self] in
            self?.launchingGameDirectory?.standardizedFileURL == directory
        }
    }
    private func summary(_ record: CofreServerRecord, index: Int, instanceID: String) -> ServerSummary {
        let host = MinecraftServerAddress.parse(record.ip)?.host ?? record.ip
        return ServerSummary(id: CofreServersStore.id(index: index, record: record), name: record.name, address: record.ip,
            hasServerCard: UserDefaults.standard.bool(forKey: "cofre.server-card.\(host)"), instanceID: instanceID, iconPNG: record.icon)
    }
    public func servers(instanceID: String) async throws -> [ServerSummary] {
        let store = try serverStore(instanceID)
        // Corrupt files look empty, but mutations still parse strictly and refuse to overwrite them.
        return ((try? store.list()) ?? []).enumerated().compactMap { index, record in
            record.hidden ? nil : summary(record, index: index, instanceID: instanceID)
        }
    }
    public func addServer(instanceID: String, name: String, address: String) async throws -> ServerSummary {
        guard MinecraftServerAddress.parse(address) != nil else { throw MinecraftServerPingError.invalidAddress }
        let store = try serverStore(instanceID)
        let index = try store.add(CofreServerRecord(name: name, ip: address))
        return summary(try store.list()[index], index: index, instanceID: instanceID)
    }
    public func removeServer(_ server: ServerSummary) async throws {
        guard let id = server.instanceID else { throw CofreServersStore.Failure.staleRecord }
        try serverStore(id).remove(id: server.id)
    }
    public func copyServer(_ server: ServerSummary, to instanceID: String) async throws -> ServerSummary {
        guard let id = server.instanceID else { throw CofreServersStore.Failure.staleRecord }
        let destination = try serverStore(instanceID)
        let index = try serverStore(id).copy(id: server.id, to: destination)
        return summary(try destination.list()[index], index: index, instanceID: instanceID)
    }
    public func pingServer(address: String) async throws -> ServerPing {
        let status = try await MinecraftServerPinger().ping(address)
        let versions = await ProtocolVersionMap.shared.versions(for: status.protocolVersion ?? -1)
        return ServerPing(motd: status.motd, online: status.online, max: status.max,
            versionName: status.versionName, protocolVersion: status.protocolVersion,
            gameVersions: versions, iconPNG: status.faviconPNG,
            latencyMS: Int(status.latency * 1000))
    }
    public func discoverServers(instanceID: String) async throws -> [ServerSummary] {
        let instance = try storedInstance(instanceID)
        let saved = Set(try serverStore(instanceID).list().map(\.ip))
        return try await ServerDirectory.recommended(version: instance.gameVersion, loader: instance.loader.rawValue, saved: saved).map {
            ServerSummary(id: $0.id, name: $0.name, address: $0.address, detail: $0.summary,
                          motd: $0.summary, playersOnline: $0.online, playersMax: $0.max, gameVersions: $0.versions)
        }
    }
    public func joinServer(instanceID: String, address: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
        do {
            guard let parsed = MinecraftServerAddress.parse(address) else { throw MinecraftServerPingError.invalidAddress }
            let instance = try storedInstance(instanceID)
            let args = MinecraftLaunchArguments.server(parsed, gameVersion: instance.gameVersion)
            NSLog("[Cofre] server quick play instance=%@ args=%@", instanceID, args.joined(separator: " "))
            return launch(instanceID: instanceID, accountID: accountID, gameArguments: args)
        } catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
    }
}
#endif
