import CryptoKit
import Foundation

struct Envelope: Codable {
    let format: String
    let payload: String
    let keyID: String
    let publicKey: String
    let signature: String
    let previousKeySignature: String?

    enum CodingKeys: String, CodingKey {
        case format, payload, signature
        case keyID = "key_id"
        case publicKey = "public_key"
        case previousKeySignature = "previous_key_signature"
    }
}
func b64(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
enum ServerCardError: LocalizedError {
    case invalidBase64(String)

    var errorDescription: String? {
        switch self {
        case .invalidBase64(let field): "invalid base64 in \(field)"
        }
    }
}
func data(_ s: String, field: String) throws -> Data {
    let normalized = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        .padding(toLength: ((s.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
    guard let decoded = Data(base64Encoded: normalized) else {
        throw ServerCardError.invalidBase64(field)
    }
    return decoded
}
func fail(_ error: Error) -> Never {
    let message = "error: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
let args = CommandLine.arguments
func usage() -> Never {
    print("server-card keygen [dir] | sign <card.json> [dir] | verify <envelope.json>")
    exit(2)
}
guard args.count > 1 else { usage() }
do {
    switch args[1] {
    case "keygen":
        let dir = URL(fileURLWithPath: args.count > 2 ? args[2] : ".")
        let key = Curve25519.Signing.PrivateKey()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(key.rawRepresentation).write(to: dir.appendingPathComponent("private.key"))
        try Data(key.publicKey.rawRepresentation).write(to: dir.appendingPathComponent("public.key"))
        print("test-only keypair written")
    case "sign":
        guard args.count > 2 else { usage() }
        let card = URL(fileURLWithPath: args[2])
        let dir = URL(fileURLWithPath: args.count > 3 ? args[3] : ".")
        let privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(contentsOf: dir.appendingPathComponent("private.key")))
        let payload = try Data(contentsOf: card)
        let env = Envelope(
            format: "cofre-card-envelope/1", payload: b64(payload), keyID: "test-key",
            publicKey: b64(privateKey.publicKey.rawRepresentation),
            signature: b64(try privateKey.signature(for: payload)), previousKeySignature: nil)
        let out = try JSONEncoder().encode(env)
        try out.write(to: card.deletingPathExtension().appendingPathExtension("envelope.json"))
        print("signed")
    case "verify":
        guard args.count > 2 else { usage() }
        let env = try JSONDecoder().decode(
            Envelope.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let key = try Curve25519.Signing.PublicKey(
            rawRepresentation: data(env.publicKey, field: "public_key"))
        guard
            key.isValidSignature(
                try data(env.signature, field: "signature"), for: try data(env.payload, field: "payload"))
        else {
            print("invalid")
            exit(1)
        }
        print("valid")
    default: usage()
    }
} catch {
    fail(error)
}
