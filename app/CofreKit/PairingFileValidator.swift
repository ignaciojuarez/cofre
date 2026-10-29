import Foundation
public enum PairingFileValidationError: Error, Equatable { case notDictionary, missing(String), wrongType(String) }
public struct PairingFileValidator {
    public static let requiredKeys = ["HostID", "HostCertificate", "HostPrivateKey", "RootCertificate", "SystemBUID"]
    public static func validate(_ data: Data) throws -> String? {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = object as? [String: Any] else { throw PairingFileValidationError.notDictionary }
        for key in requiredKeys { guard dict[key] != nil else { throw PairingFileValidationError.missing(key) } }
        for key in ["HostCertificate", "HostPrivateKey", "RootCertificate"] { guard dict[key] is Data else { throw PairingFileValidationError.wrongType(key) } }
        return dict["UDID"] as? String
    }
}
