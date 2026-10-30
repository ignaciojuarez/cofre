import Foundation

/// Small client for the Modrinth v2 API. Responses are deliberately limited to fields Cofre consumes.
public final class Modrinth {
    public struct SearchResult: Codable, Sendable {
        public let projectID: String
        public let slug: String?
        public let title: String
        public let description: String
        public let projectType: String
        public let categories: [String]
        public let downloads: Int
        /// Kept as text: Modrinth sends "" for projects without an icon, which isn't a valid URL to decode.
        let icon: String?
        public var iconURL: URL? { Modrinth.url(icon) }
        /// Search hits carry no page link; it follows from the type and slug.
        public var pageURL: URL? { slug.flatMap { Modrinth.url("https://modrinth.com/\(projectType)/\($0)") } }
        enum CodingKeys: String, CodingKey { case projectID = "project_id", slug, title, description, projectType = "project_type", categories, downloads, icon = "icon_url" }
    }
    public struct Project: Codable, Sendable {
        public let id: String; public let title: String; public let description: String?; let icon: String?; public let projectType: String
        public var iconURL: URL? { Modrinth.url(icon) }
        enum CodingKeys: String, CodingKey { case id, title, description, icon = "icon_url", projectType = "project_type" }
    }
    public struct Version: Codable, Sendable { public let id: String; public let projectID: String; public let name: String; public let versionNumber: String; public let gameVersions: [String]; public let loaders: [String]; public let versionType: String; public let dependencies: [Dependency]; public let files: [File]; enum CodingKeys: String, CodingKey { case id, projectID = "project_id", name, versionNumber = "version_number", gameVersions = "game_versions", loaders, versionType = "version_type", dependencies, files } }
    public struct Dependency: Codable, Sendable { public let versionID: String?; public let projectID: String?; public let dependencyType: String; enum CodingKeys: String, CodingKey { case versionID = "version_id", projectID = "project_id", dependencyType = "dependency_type" } }
    public struct File: Codable, Sendable { public let hashes: [String: String]; public let url: URL?; public let filename: String; public let size: Int64; public let primary: Bool }

    private let session: URLSession
    private var cache: [String: (Date, Data)] = [:]
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    public init(session: URLSession? = nil) {
        if let session { self.session = session } else {
            let config = URLSessionConfiguration.default
            config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 16 * 1024 * 1024)
            config.requestCachePolicy = .useProtocolCachePolicy
            self.session = URLSession(configuration: config)
        }
    }
    public func search(query: String, facets: [[String]] = [], index: String = "relevance", offset: Int = 0, limit: Int = 50) async throws -> [SearchResult] {
        struct Response: Codable { let hits: [SearchResult] }
        var q: [URLQueryItem] = [.init(name: "query", value: query), .init(name: "index", value: index), .init(name: "offset", value: "\(offset)"), .init(name: "limit", value: "\(limit)")]
        if !facets.isEmpty { q.append(.init(name: "facets", value: try String(data: JSONEncoder().encode(facets), encoding: .utf8))) }
        return try await get("search", query: q, as: Response.self).hits
    }
    public func project(id: String) async throws -> Project { try await get("project/\(id)", as: Project.self) }
    public func versions(projectID: String, loaders: [String] = [], gameVersions: [String] = []) async throws -> [Version] {
        var q: [URLQueryItem] = []
        if !loaders.isEmpty { q.append(.init(name: "loaders", value: try json(loaders))) }
        if !gameVersions.isEmpty { q.append(.init(name: "game_versions", value: try json(gameVersions))) }
        return try await get("project/\(projectID)/version", query: q, as: [Version].self)
    }
    public func versionFiles(hashes: [String]) async throws -> [String: Version] {
        let body = try JSONSerialization.data(withJSONObject: ["hashes": hashes, "algorithm": "sha1"])
        return try await post("version_file", body: body, as: [String: Version].self)
    }
    public func projects(ids: [String]) async throws -> [Project] {
        try await post("projects", body: try JSONSerialization.data(withJSONObject: ["ids": ids]), as: [Project].self)
    }
    static func url(_ text: String?) -> URL? { text.flatMap { $0.isEmpty ? nil : URL(string: $0) } }
    private func json(_ value: [String]) throws -> String { String(data: try JSONEncoder().encode(value), encoding: .utf8)! }
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T { try await request(path, query: query, method: "GET", body: nil, as: type) }
    private func post<T: Decodable>(_ path: String, body: Data, as type: T.Type) async throws -> T { try await request(path, query: [], method: "POST", body: body, as: type) }
    private func request<T: Decodable>(_ path: String, query: [URLQueryItem], method: String, body: Data?, as type: T.Type) async throws -> T {
        var components = URLComponents(string: "https://api.modrinth.com/v2/\(path)")!; components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 15; request.setValue("ignaciojuarez/cofre (github.com/ignaciojuarez/cofre)", forHTTPHeaderField: "User-Agent")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let key = request.url!.absoluteString + method + (body.map { String(decoding: $0, as: UTF8.self) } ?? "")
        if method == "GET", let hit = lock.withLock({ cache[key].flatMap { Date().timeIntervalSince($0.0) < 30 ? $0.1 : nil } }) { return try decoder.decode(T.self, from: hit) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NSError(domain: "Modrinth", code: (response as? HTTPURLResponse)?.statusCode ?? 0) }
        if method == "GET" { lock.withLock { cache[key] = (Date(), data) } }
        return try decoder.decode(T.self, from: data)
    }
}

private extension NSLock { func withLock<T>(_ body: () throws -> T) rethrows -> T { lock(); defer { unlock() }; return try body() } }
