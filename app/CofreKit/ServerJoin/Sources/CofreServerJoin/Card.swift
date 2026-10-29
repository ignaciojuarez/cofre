import Foundation

public enum ServerJoinError: Error, Equatable, Sendable {
    case invalidCard(String)
    case invalidEnvelope(String)
    case insecureURL
    case hostNotAllowed(String)
    case sizeLimit
    case pathTraversal(String)
    case invalidDeepLink, signatureInvalid, keyChanged
    case hashMismatch
    case filesystem(String)
    case download(String)
}

public struct ServerAddress: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}
public enum Loader: String, Codable, Sendable { case vanilla, fabric, quilt, forge, neoforge }
public struct LoaderRequirement: Codable, Equatable, Sendable {
    public let type: Loader
    public let version: String
}
public struct PackRequirement: Codable, Equatable, Sendable {
    public let type: String
    public let url: URL
    public let sha512: String
    public let version: String
    public let sizeBytes: Int64?
    enum CodingKeys: String, CodingKey {
        case type, url, sha512, version
        case sizeBytes = "size_bytes"
    }
}
public struct CardSecurity: Codable, Equatable, Sendable {
    public let origin: URL
    public let allowedHosts: [String]
    public let trust: String
    public let maxBytes: Int64
    enum CodingKeys: String, CodingKey {
        case origin
        case allowedHosts = "allowed_hosts"
        case trust
        case maxBytes = "max_bytes"
    }
}
public struct ContentItem: Codable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let required: Bool?
    public let sizeBytes: Int64?
}
public struct IOSOverrides: Codable, Equatable, Sendable {
    public let exclude: [String]
    public let replace: [Replacement]
    public let compatibility: [String: String]?
    public struct Replacement: Codable, Equatable, Sendable {
        public let id: String
        public let with: String
    }
}
public struct PlatformOverrides: Codable, Equatable, Sendable { public let ios: IOSOverrides? }
public struct ServerCard: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let server: Server
    public let game: Game
    public let loader: LoaderRequirement
    public let pack: PackRequirement
    public let content: Content?
    public let recommendedRAMMB: Int?
    public let platformOverrides: PlatformOverrides?
    public let updatePolicy: String
    public let security: CardSecurity
    public let changelog: String?
    public struct Server: Codable, Equatable, Sendable {
        public let name: String
        public let addresses: [ServerAddress]
        public let icon: URL?
        public let network: String?
    }
    public struct Game: Codable, Equatable, Sendable {
        public let version: String
        public let javaVersion: Int
        enum CodingKeys: String, CodingKey {
            case version
            case javaVersion = "java_version"
        }
    }
    public struct Content: Codable, Equatable, Sendable {
        public let resourcePacks: [ContentItem]?
        public let shaders: [ContentItem]?
        public let clientMods: [ContentItem]?
        public let optionalMods: [ContentItem]?
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id, server, game, loader, pack, content
        case recommendedRAMMB = "recommended_ram_mb"
        case platformOverrides = "platform_overrides"
        case updatePolicy = "update_policy"
        case security, changelog
    }
}
