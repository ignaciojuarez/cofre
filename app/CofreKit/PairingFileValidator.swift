import Foundation

public enum PairingFileValidationError: Error, Equatable {
    case notDictionary
    case missing(String)
    case wrongType(String)
    case empty(String)
    case tooLarge(String)
    case invalid(String)
}

public enum PairingFileValidator {
    public static let requiredKeys = [
        "HostID", "HostCertificate", "HostPrivateKey", "RootCertificate", "RootPrivateKey", "SystemBUID", "UDID",
    ]
    private static let maxString = 256
    private static let maxBlob = 64 * 1024
    @discardableResult public static func validate(_ data: Data, requireRemotePairing: Bool = false) throws -> String {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else { throw PairingFileValidationError.notDictionary }
        for key in requiredKeys { guard dict[key] != nil else { throw PairingFileValidationError.missing(key) } }
        for key in ["HostID", "SystemBUID", "UDID"] {
            guard let value = dict[key] as? String else { throw PairingFileValidationError.wrongType(key) }
            guard !value.isEmpty, value.count <= maxString else { throw PairingFileValidationError.invalid(key) }
        }
        for key in ["HostCertificate", "HostPrivateKey", "RootCertificate", "RootPrivateKey"] {
            guard let value = dict[key] as? Data else { throw PairingFileValidationError.wrongType(key) }
            guard !value.isEmpty else { throw PairingFileValidationError.empty(key) }
            guard value.count <= maxBlob else { throw PairingFileValidationError.tooLarge(key) }
        }
        if requireRemotePairing {
            for key in ["EscrowBag", "PairingCertificate", "PairingPrivateKey"] {
                guard let value = dict[key] as? Data, !value.isEmpty else {
                    throw PairingFileValidationError.missing(key)
                }
            }
        }
        return dict["UDID"] as! String
    }
}
