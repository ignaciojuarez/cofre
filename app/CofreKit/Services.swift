import Foundation

public final class FilePairingStore: PairingStore {
    private let url: URL
    public init(
        url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pairing.bin")
    ) { self.url = url }
    public func hasPairing() -> Bool { FileManager.default.fileExists(atPath: url.path) }
    public func importPairing(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .completeFileProtection)
    }
    public func deletePairing() throws { if hasPairing() { try FileManager.default.removeItem(at: url) } }
}
