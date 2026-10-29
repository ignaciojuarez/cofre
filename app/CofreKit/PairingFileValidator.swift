import Foundation

public enum PairingFileValidationError: Error, Equatable {
    case notDictionary
    case missing(String)
    case wrongType(String)
}

public struct PairingFileValidator {
    public static let requiredKeys = [
        "HostID",
        "HostCertificate",
        "HostPrivateKey",
        "RootCertificate",
        "SystemBUID"
    ]

    @discardableResult
    public static func validate(_ data: Data) throws -> String? {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw PairingFileValidationError.notDictionary
        }

        for key in requiredKeys {
            guard dict[key] != nil else {
                throw PairingFileValidationError.missing(key)
            }
        }

        for key in ["HostCertificate", "HostPrivateKey", "RootCertificate"] {
            guard dict[key] is Data else {
                throw PairingFileValidationError.wrongType(key)
            }
        }

        return dict["UDID"] as? String
    }
}
