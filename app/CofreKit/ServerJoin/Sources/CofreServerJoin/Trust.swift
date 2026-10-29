import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif
public struct TrustRecord: Codable, Equatable, Sendable {
    public let origin: String
    public let keyID: String
    public let fingerprint: String
}
public protocol TrustStore: Sendable {
    func record(for origin: String) async -> TrustRecord?
    func save(_ record: TrustRecord) async
}
public actor MemoryTrustStore: TrustStore {
    private var records: [String: TrustRecord] = [:]
    public init() {}
    public func record(for origin: String) -> TrustRecord? { records[origin] }
    public func save(_ record: TrustRecord) { records[record.origin] = record }
}
public actor FileTrustStore: TrustStore {
    private let url: URL
    private var records: [String: TrustRecord] = [:]
    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode([String: TrustRecord].self, from: data)
        {
            records = value
        }
    }
    public func record(for origin: String) -> TrustRecord? { records[origin] }
    public func save(_ record: TrustRecord) {
        records[record.origin] = record
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {}
    }
}
public struct TrustDecision: Equatable, Sendable {
    public let firstVisit: Bool
    public let origin: String
    public let fingerprint: String
    public let keyChanged: Bool
    public let pinnedFingerprint: String?
}
public enum TrustVerifier {
    public static func evaluate(card: ServerCard, envelope: CardEnvelope, store: TrustStore) async -> TrustDecision {
        let origin = card.security.origin.absoluteString
        let fingerprint = envelope.publicKey
        guard let old = await store.record(for: origin) else {
            return TrustDecision(
                firstVisit: true, origin: origin, fingerprint: fingerprint, keyChanged: false, pinnedFingerprint: nil)
        }
        if old.fingerprint == fingerprint {
            return TrustDecision(
                firstVisit: false, origin: origin, fingerprint: fingerprint, keyChanged: false, pinnedFingerprint: nil)
        }
        let rotated =
            envelope.previousKeySignature.flatMap { Data(base64URL: $0) }.map { signature in
                #if canImport(CryptoKit)
                    guard let oldKeyData = Data(base64URL: old.fingerprint),
                        let oldKey = try? Curve25519.Signing.PublicKey(rawRepresentation: oldKeyData),
                        let newKey = Data(base64URL: fingerprint)
                    else { return false }
                    return oldKey.isValidSignature(signature, for: newKey)
                #else
                    return false
                #endif
            } ?? false
        return TrustDecision(
            firstVisit: false, origin: origin, fingerprint: fingerprint, keyChanged: !rotated,
            pinnedFingerprint: old.fingerprint)
    }
    public static func confirm(card: ServerCard, envelope: CardEnvelope, store: TrustStore) async {
        await store.save(
            TrustRecord(
                origin: card.security.origin.absoluteString, keyID: envelope.keyID, fingerprint: envelope.publicKey))
    }
}
extension Data {
    fileprivate init?(base64URL value: String) {
        self.init(
            base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                .padding(toLength: ((value.count + 3) / 4) * 4, withPad: "=", startingAt: 0))
    }
}
