import Foundation

public enum ServerDirectory {
    public struct Entry: Sendable {
        public let id: String, name: String, address: String, summary: String
        public let versions: [String]
        public let online: Int?, max: Int?
    }
    public static func recommended(version: String, loader: String, saved: Set<String>) async throws -> [Entry] {
        var url = URLComponents(string: "https://api.modrinth.com/v3/search")!
        let facets = [["project_types:minecraft_java_server"], ["game_versions:\(version)"]]
        url.queryItems = [URLQueryItem(name: "facets", value: String(data: try JSONEncoder().encode(facets), encoding: .utf8)),
                          URLQueryItem(name: "index", value: "follows"), URLQueryItem(name: "limit", value: "100")]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 15
        request.setValue("Cofre/1.0 (github.com/ignaciojuarez/cofre)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try decode(data, version: version, loader: loader, saved: saved)
    }
    public static func decode(_ data: Data, version: String, loader: String, saved: Set<String>) throws -> [Entry] {
        let hits = try JSONDecoder().decode(Response.self, from: data).hits
        var seen = Set(saved.map(MinecraftServerAddress.key))
        return Array(hits.compactMap { hit -> Entry? in
            guard hit.game_versions.contains(version), let server = hit.minecraft_java_server,
                  MinecraftServerAddress.parse(server.address) != nil else { return nil }
            let loaders = hit.mrpack_loaders ?? hit.project_loader_fields?.mrpack_loaders ?? []
            guard loaders.isEmpty || loaders.contains(loader), seen.insert(MinecraftServerAddress.key(server.address)).inserted else { return nil }
            return Entry(id: hit.project_id, name: hit.name, address: server.address, summary: hit.summary,
                         versions: hit.game_versions, online: server.ping?.data?.players_online, max: server.ping?.data?.players_max)
        }.prefix(20))
    }
    private struct Response: Decodable { let hits: [Hit] }
    private struct Hit: Decodable {
        let project_id: String, name: String, summary: String
        let game_versions: [String]
        let mrpack_loaders: [String]?
        let project_loader_fields: Fields?
        let minecraft_java_server: Server?
    }
    private struct Fields: Decodable { let mrpack_loaders: [String]? }
    private struct Server: Decodable { let address: String; let ping: Ping? }
    private struct Ping: Decodable { let data: Status? }
    private struct Status: Decodable { let players_online: Int?; let players_max: Int? }
}
