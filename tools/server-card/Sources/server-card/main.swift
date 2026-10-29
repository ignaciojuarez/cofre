import Foundation
import CryptoKit
struct Envelope: Codable { let format: String; let payload: String; let key_id: String; let public_key: String; let signature: String; let previous_key_signature: String? }
func b64(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
func data(_ s: String) -> Data { Data(base64Encoded: s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").padding(toLength: ((s.count + 3) / 4) * 4, withPad: "=", startingAt: 0))! }
let args = CommandLine.arguments
func usage() -> Never { print("server-card keygen [dir] | sign <card.json> [dir] | verify <envelope.json>"); exit(2) }
guard args.count > 1 else { usage() }
switch args[1] {
case "keygen":
    let dir = URL(fileURLWithPath: args.count > 2 ? args[2] : "."); let key = Curve25519.Signing.PrivateKey(); try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try! Data(key.rawRepresentation).write(to: dir.appendingPathComponent("private.key")); try! Data(key.publicKey.rawRepresentation).write(to: dir.appendingPathComponent("public.key")); print("test-only keypair written")
case "sign":
    guard args.count > 2 else { usage() }; let card = URL(fileURLWithPath: args[2]); let dir = URL(fileURLWithPath: args.count > 3 ? args[3] : "."); let privateKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: dir.appendingPathComponent("private.key"))); let payload = try! Data(contentsOf: card); let env = Envelope(format: "cofre-card-envelope/1", payload: b64(payload), key_id: "test-key", public_key: b64(privateKey.publicKey.rawRepresentation), signature: b64(try! privateKey.signature(for: payload)), previous_key_signature: nil); let out = try! JSONEncoder().encode(env); try! out.write(to: card.deletingPathExtension().appendingPathExtension("envelope.json")); print("signed")
case "verify":
    guard args.count > 2 else { usage() }; let env = try! JSONDecoder().decode(Envelope.self, from: Data(contentsOf: URL(fileURLWithPath: args[2]))); let key = try! Curve25519.Signing.PublicKey(rawRepresentation: data(env.public_key)); guard key.isValidSignature(data(env.signature), for: data(env.payload)) else { print("invalid"); exit(1) }; print("valid")
default: usage()
}
