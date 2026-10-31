import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif
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
    public func verify(fileURL: URL, card: ServerCard) throws {
        let expected = card.pack.sizeBytes ?? card.security.maxBytes
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        #if canImport(CryptoKit)
            var hasher = SHA512()
        #endif
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            count += Int64(chunk.count)
            guard count <= expected else { throw ServerJoinError.sizeLimit }
            #if canImport(CryptoKit)
                hasher.update(data: chunk)
            #endif
        }
        guard count == expected else { throw ServerJoinError.hashMismatch }
        #if canImport(CryptoKit)
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest.caseInsensitiveCompare(card.pack.sha512) == .orderedSame else {
                throw ServerJoinError.hashMismatch
            }
        #else
            throw ServerJoinError.hashMismatch
        #endif
    }

}
