import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public protocol CardFetcher: Sendable { func fetch(_ url: URL) async throws -> Data }
public struct URLSessionCardFetcher: CardFetcher {
    public init() {}
    public func fetch(_ url: URL) async throws -> Data {
        let validated = try URLPolicy.validate(url, allowedHosts: [url.host ?? ""])
        let delegate = RedirectPolicy(allowedHosts: [validated.host ?? ""])
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: validated)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServerJoinError.download("HTTP") }
        guard data.count <= 512 * 1024 else { throw ServerJoinError.sizeLimit }
        return data
    }
}

public enum URLPolicy {
    public static func canonicalHost(_ host: String) -> String? {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        guard !value.isEmpty else { return nil }
        return value.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false)?.lowercased()
            .trimmingCharacters(
                in: CharacterSet(charactersIn: ".")) ?? value
    }
    public static func validate(_ url: URL, allowedHosts: [String]) throws -> URL {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
            let host = url.host, let canonical = canonicalHost(host), !canonical.isEmpty
        else { throw ServerJoinError.insecureURL }
        let allowed = allowedHosts.compactMap { value -> (String, Int?)? in
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard let name = canonicalHost(parts[0]) else { return nil }
            return (name, parts.count == 2 ? Int(parts[1]) : nil)
        }
        let port = url.port ?? 443
        guard allowed.contains(where: { $0.0 == canonical && ($0.1 == nil ? port == 443 : $0.1 == port) }) else {
            throw ServerJoinError.hostNotAllowed("\(host):\(port)")
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = canonical
        components?.port = url.port
        return components?.url ?? url
    }
}

final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: [String]
    init(allowedHosts: [String]) { self.allowedHosts = allowedHosts }
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, let checked = try? URLPolicy.validate(url, allowedHosts: allowedHosts)
        else {
            completionHandler(nil)
            return
        }
        var next = request
        next.url = checked
        completionHandler(next)
    }
}

public struct PackDownload: Sendable {
    public let fileURL: URL
    public let byteCount: Int64
    public let sha512: String
}
public protocol PackDownloader: Sendable {
    func download(_ url: URL, allowedHosts: [String], maxBytes: Int64, expectedSHA512: String) async throws
        -> PackDownload
}
public struct URLSessionPackDownloader: PackDownloader {
    public init() {}
    public func download(_ url: URL, allowedHosts: [String], maxBytes: Int64, expectedSHA512: String) async throws
        -> PackDownload
    {
        let initial = try URLPolicy.validate(url, allowedHosts: allowedHosts)
        let delegate = RedirectPolicy(allowedHosts: allowedHosts)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: initial)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServerJoinError.download("HTTP") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("cofre-pack-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer {
            try? handle.close()
            if Task.isCancelled { try? FileManager.default.removeItem(at: output) }
        }
        var count: Int64 = 0
        #if canImport(CryptoKit)
            var hasher = CryptoKit.SHA512()
        #endif
        do {
            for try await byte in bytes {
                count += 1
                guard count <= maxBytes else { throw ServerJoinError.sizeLimit }
                let chunk = Data([byte])
                try handle.write(contentsOf: chunk)
                #if canImport(CryptoKit)
                    hasher.update(data: chunk)
                #endif
            }
            #if canImport(CryptoKit)
                let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                guard digest.caseInsensitiveCompare(expectedSHA512) == .orderedSame else {
                    throw ServerJoinError.hashMismatch
                }
                return PackDownload(fileURL: output, byteCount: count, sha512: digest)
            #else
                throw ServerJoinError.hashMismatch
            #endif
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }

    }
}

public enum Discovery {
    public static func deepLink(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "cofre", url.host?.lowercased() == "join",
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
                $0.name == "card"
            })?.value,
            let card = URL(string: raw), card.scheme?.lowercased() == "https"
        else { throw ServerJoinError.invalidDeepLink }
        return card
    }

    /// Decodes a join link and binds its optional advertised server to the card's addresses.
    public static func deepLink(_ url: URL, card: ServerCard) throws -> URL {
        let cardURL = try deepLink(url)
        guard let advertised = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
            $0.name == "server"
        })?.value else { return cardURL }
        let parts = advertised.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = URLPolicy.canonicalHost(parts[0]),
            let port = parts.count == 2 ? Int(parts[1]) : 25565,
            card.server.addresses.contains(where: {
                URLPolicy.canonicalHost($0.host) == host && $0.port == port
            })
        else { throw ServerJoinError.invalidDeepLink }
        return cardURL
    }
    public static func wellKnown(host: String) -> URL {
        URL(string: "https://\(host)/.well-known/minecraft-server-card.json")!
    }
    public static func fetchEnvelope(from url: URL, using fetcher: CardFetcher) async throws -> (
        ServerCard, CardEnvelope
    ) {
        let result = try CardDecoder.decodeEnvelope(try await fetcher.fetch(url))
        return (result.card, result.envelope)
    }
}
