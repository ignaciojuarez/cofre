import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif
public protocol JoinFileSystem: Sendable {
    func makeStaging(_ id: String) throws
    func write(_ data: Data, at path: String) throws
    func atomicSwap(_ id: String) throws
    func rollback(_ id: String) throws
    func removeStaging(_ id: String) throws
}
public protocol JoinDownloader: Sendable { func download(_ url: URL, resumeData: Data?) async throws -> (Data, Data?) }
public protocol HashCache: Sendable {
    func data(for sha512: String) throws -> Data?
    func put(_ data: Data, sha512: String) throws
}
public final class FileHashCache: HashCache, @unchecked Sendable {
    private let root: URL
    public init(root: URL) { self.root = root }
    public func data(for sha512: String) throws -> Data? {
        let url = root.appendingPathComponent(sha512)
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
    public func put(_ data: Data, sha512: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent(sha512), options: .atomic)
    }
}
public actor InstallEngine {
    private let cache: HashCache?
    public init(cache: HashCache? = nil) { self.cache = cache }
    public func install(card: ServerCard, data: Data, filesystem: JoinFileSystem) throws {
        try filesystem.makeStaging(card.id)
        do {
            guard data.count <= 2_147_483_648 else { throw ServerJoinError.sizeLimit }
            #if canImport(CryptoKit)
                let digest = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest.caseInsensitiveCompare(card.pack.sha512) == .orderedSame else {
                    throw ServerJoinError.hashMismatch
                }
            #endif
            try cache?.put(data, sha512: card.pack.sha512)
            try filesystem.write(data, at: "pack.mrpack")
            try filesystem.atomicSwap(card.id)
        } catch {
            try? filesystem.removeStaging(card.id)
            try? filesystem.rollback(card.id)
            throw error
        }
    }
}
