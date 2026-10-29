import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

public struct CardEnvelope: Codable, Equatable, Sendable {
    public let format: String
    public let payload: String
    public let keyID: String
    public let publicKey: String
    public let signature: String
    public let previousKeySignature: String?
    enum CodingKeys: String, CodingKey {
        case format, payload
        case keyID = "key_id"
        case publicKey = "public_key"
        case signature
        case previousKeySignature = "previous_key_signature"
    }
}
public enum CardDecoder {
    public static func decodeEnvelope(_ data: Data) throws -> (card: ServerCard, envelope: CardEnvelope, payload: Data)
    {
        guard data.count <= 512 * 1024 else { throw ServerJoinError.sizeLimit }
        let envelope = try JSONDecoder().decode(CardEnvelope.self, from: data)
        guard envelope.format == "cofre-card-envelope/1", let payload = Data(base64URL: envelope.payload) else {
            throw ServerJoinError.invalidEnvelope("format/payload")
        }
        guard envelope.publicKey.count == 43, envelope.signature.count == 86 else {
            throw ServerJoinError.invalidEnvelope("key/signature")
        }
        try verify(envelope: envelope, payload: payload)
        return (try decodeCard(payload), envelope, payload)
    }
    public static func decodeCard(_ data: Data) throws -> ServerCard {
        guard data.count <= 512 * 1024 else { throw ServerJoinError.sizeLimit }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let allowed = Set([
            "schema_version", "id", "server", "game", "loader", "pack", "content", "recommended_ram_mb",
            "min_launcher_version", "platform_overrides", "changelog", "update_policy", "security", "signing",
        ])
        guard Set(object.keys).isSubset(of: allowed) else { throw ServerJoinError.invalidCard("unknown field") }
        let card: ServerCard
        do { card = try JSONDecoder().decode(ServerCard.self, from: data) } catch {
            throw ServerJoinError.invalidCard(error.localizedDescription)
        }
        guard card.schemaVersion == "1.0.0",
            card.id.range(of: "^[a-z0-9][a-z0-9.-]{0,62}$", options: .regularExpression) != nil
        else { throw ServerJoinError.invalidCard("schema/id") }
        guard card.security.origin.scheme == "https", card.pack.url.scheme == "https" else {
            throw ServerJoinError.insecureURL
        }
        guard
            card.security.allowedHosts.allSatisfy({
                !$0.contains("*") && $0.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil
            })
        else { throw ServerJoinError.invalidCard("wildcard host") }
        guard card.security.allowedHosts.contains(card.security.origin.host ?? ""),
            card.security.allowedHosts.contains(card.pack.url.host ?? "")
        else { throw ServerJoinError.hostNotAllowed(card.pack.url.host ?? "") }
        guard card.pack.sha512.range(of: "^[A-Fa-f0-9]{128}$", options: .regularExpression) != nil,
            (card.pack.sizeBytes ?? 0) <= 2_147_483_648
        else { throw ServerJoinError.invalidCard("pack hash/size") }
        if let ios = card.platformOverrides?.ios {
            for path in ios.exclude where path.contains("..") || path.hasPrefix("/") {
                throw ServerJoinError.pathTraversal(path)
            }
        }
        return card
    }
    public static func verify(envelope: CardEnvelope, payload: Data) throws {
        #if canImport(CryptoKit)
            guard let keyData = Data(base64URL: envelope.publicKey), let sig = Data(base64URL: envelope.signature),
                let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
                key.isValidSignature(sig, for: payload)
            else { throw ServerJoinError.signatureInvalid }
        #else
            throw ServerJoinError.signatureInvalid
        #endif
    }
}
extension Data {
    fileprivate init?(base64URL value: String) {
        self.init(
            base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                .padding(toLength: ((value.count + 3) / 4) * 4, withPad: "=", startingAt: 0))
    }
}
