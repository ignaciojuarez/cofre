import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Update: Sendable, Equatable {
    public let version: String
    public let notes: String
    public let installURL: URL
    public init(version: String, notes: String, installURL: URL) {
        self.version = version; self.notes = notes; self.installURL = installURL
    }
}

/// Checks GitHub Releases once per process launch. Network failures are intentionally silent.
public actor UpdateChecker {
    public static let endpoint = URL(string: "https://api.github.com/repos/ignaciojuarez/cofre/releases/latest")!
    private let session: URLSession
    private let installedBuildNumber: Int
    private let defaults: UserDefaults
    private var didCheck = false

    public init(installedBuildNumber: Int? = nil, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.installedBuildNumber = installedBuildNumber ?? (Bundle.main.object(forInfoDictionaryKey: "CofreBuildNumber") as? Int ?? Int(Bundle.main.object(forInfoDictionaryKey: "CofreBuildNumber") as? String ?? "0") ?? 0)
        self.defaults = defaults
    }

    public func check() async -> Update? {
        guard !didCheck else { return nil }
        didCheck = true
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Cofre-iOS", forHTTPHeaderField: "User-Agent")
        if let etag = defaults.string(forKey: "cofre.update.etag") { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 304 || http.statusCode == 404 || http.statusCode == 403 || http.statusCode == 429 { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            if let etag = http.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: "cofre.update.etag") }
            return Self.parse(data: data, installedBuildNumber: installedBuildNumber)
        } catch { return nil }
    }

    public static func parse(data: Data, installedBuildNumber: Int) -> Update? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let build = Int(tag.split(separator: ".").last ?? ""), build > installedBuildNumber,
              let assets = object["assets"] as? [[String: Any]] else { return nil }
        guard let manifestString = assets.first(where: { ($0["name"] as? String) == "manifest.plist" })?["browser_download_url"] as? String,
              let manifestURL = URL(string: manifestString),
              assets.contains(where: { ($0["name"] as? String) == "Cofre.ipa" }) else { return nil }
        var components = URLComponents(); components.scheme = "itms-services"; components.queryItems = [URLQueryItem(name: "action", value: "download-manifest"), URLQueryItem(name: "url", value: manifestURL.absoluteString)]
        guard let installURL = components.url else { return nil }
        return Update(version: tag, notes: object["body"] as? String ?? "", installURL: installURL)
    }
}
