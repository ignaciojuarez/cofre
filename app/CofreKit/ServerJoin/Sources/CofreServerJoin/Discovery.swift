import Foundation
public protocol CardFetcher: Sendable { func fetch(_ url: URL) async throws -> Data }
public struct URLSessionCardFetcher: CardFetcher { public init() {} ; public func fetch(_ url: URL) async throws -> Data { let (data,response) = try await URLSession.shared.data(from: url); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServerJoinError.download("HTTP") }; return data } }
public enum Discovery {
    public static func deepLink(_ url: URL) throws -> URL { guard url.scheme == "cofre", url.host == "join", let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "card" })?.value, let card = URL(string: raw), card.scheme == "https" else { throw ServerJoinError.invalidDeepLink }; return card }
    public static func wellKnown(host: String) -> URL { URL(string: "https://\(host)/.well-known/minecraft-server-card.json")! }
    public static func fetchEnvelope(from url: URL, using fetcher: CardFetcher) async throws -> (ServerCard, CardEnvelope) { let result = try CardDecoder.decodeEnvelope(try await fetcher.fetch(url)); return (result.card, result.envelope) }
}
