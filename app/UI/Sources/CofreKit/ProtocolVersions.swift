import Foundation

/// PrismarineJS minecraft-data protocol mappings, refreshed over HTTPS and cached briefly.
public actor ProtocolVersionMap {
    public static let shared = ProtocolVersionMap()
    public static let source = URL(string: "https://raw.githubusercontent.com/PrismarineJS/minecraft-data/master/data/pc/common/protocolVersions.json")!
    private let ttl: TimeInterval = 7 * 24 * 60 * 60
    private var values: [Int: [String]] = [:]
    public init() {}
    public func versions(for protocolVersion: Int) async -> [String] {
        if values.isEmpty { await refresh() }
        return values[protocolVersion] ?? []
    }
    public func parse(_ data: Data) throws -> [Int: [String]] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let list = object as? [[String: Any]] else { throw NSError(domain: "protocolVersions", code: 1) }
        var result: [Int: [String]] = [:]
        for item in list {
            guard let protocolID = item["version"] as? Int else { continue }
            let name = (item["minecraftVersion"] as? String) ?? (item["name"] as? String)
            if let name { result[protocolID, default: []].append(name) }
        }
        return result
    }
    private func refresh() async {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("cofre-protocol-versions.json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path), let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < ttl,
           let data = try? Data(contentsOf: cache), let parsed = try? parse(data) { values = parsed; return }
        if let (data, _) = try? await URLSession.shared.data(from: Self.source), let parsed = try? parse(data) {
            values = parsed; try? data.write(to: cache, options: .atomic); return
        }
        if let data = try? Data(contentsOf: Bundle.module.url(forResource: "protocolVersions", withExtension: "json")!), let parsed = try? parse(data) { values = parsed }
    }
}
