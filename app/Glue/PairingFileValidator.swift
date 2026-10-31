import Foundation

public enum PairingFileValidationError: Error, Equatable, LocalizedError {
    case notDictionary
    case missing(String)
    case wrongType(String)
    case empty(String)
    case tooLarge(String)
    case invalid(String)
    case remotePairingMissing([String])

    public var errorDescription: String? {
        switch self {
        case .notDictionary, .invalid("plist"):
            "This pairing file is not a valid plist. Run the Mac pairing command again."
        case .missing(let key):
            "This pairing file is missing \(key). Run the Mac pairing command again."
        case .wrongType(let key), .empty(let key), .invalid(let key):
            "This pairing file has invalid \(key) data. Run the Mac pairing command again."
        case .tooLarge("file"):
            "This pairing file is too large. Choose the file produced by the Mac pairing command."
        case .tooLarge(let key):
            "This pairing file has an oversized \(key) value. Run the Mac pairing command again."
        case .remotePairingMissing:
            "This pairing file has no RemotePairing data. On iOS 17.4 and later, run the Mac pairing command again."
        }
    }
}

public enum PairingFileValidator {
    public static let maxFileSize = 4 * 1024 * 1024
    public static let requiredKeys = [
        "DeviceCertificate", "HostID", "HostCertificate", "HostPrivateKey", "RootCertificate", "RootPrivateKey", "SystemBUID", "UDID",
    ]
    private static let maxString = 256
    private static let maxBlob = 64 * 1024
    public static var requiresRemotePairing: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (version.majorVersion, version.minorVersion) >= (17, 4)
    }

    @discardableResult
    public static func validate(
        _ data: Data,
        requireRemotePairing: Bool = PairingFileValidator.requiresRemotePairing
    ) throws -> String {
        guard data.count <= maxFileSize else { throw PairingFileValidationError.tooLarge("file") }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw PairingFileValidationError.invalid("plist")
        }
        guard let dict = object as? [String: Any] else { throw PairingFileValidationError.notDictionary }
        try validateBlobSizes(in: dict)
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
            let keys = ["public_key", "private_key", "identifier"]
            let missing = keys.filter { dict[$0] == nil }
            if !missing.isEmpty { throw PairingFileValidationError.remotePairingMissing(missing) }
            for key in ["public_key", "private_key"] {
                guard let value = dict[key] as? Data else { throw PairingFileValidationError.wrongType(key) }
                guard value.count == 32 else { throw PairingFileValidationError.invalid(key) }
            }
            guard let identifier = dict["identifier"] as? String else {
                throw PairingFileValidationError.wrongType("identifier")
            }
            guard !identifier.isEmpty, identifier.count <= maxString else {
                throw PairingFileValidationError.invalid("identifier")
            }
        }
        return dict["UDID"] as! String
    }

    private static func validateBlobSizes(in value: Any, key: String? = nil) throws {
        if let data = value as? Data {
            guard data.count <= maxBlob else { throw PairingFileValidationError.tooLarge(key ?? "blob") }
        } else if let dict = value as? [String: Any] {
            for (childKey, childValue) in dict { try validateBlobSizes(in: childValue, key: childKey) }
        } else if let array = value as? [Any] {
            for childValue in array { try validateBlobSizes(in: childValue, key: key) }
        }
    }
}

public enum PairingFileStore {
    public static func importFile(at source: URL) throws {
        guard source.isFileURL else { throw PairingFileValidationError.invalid("file") }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let size = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber,
              size.uint64Value <= UInt64(PairingFileValidator.maxFileSize) else {
            throw PairingFileValidationError.tooLarge("file")
        }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PairingFileValidator.maxFileSize + 1) ?? Data()
        guard data.count <= PairingFileValidator.maxFileSize else {
            throw PairingFileValidationError.tooLarge("file")
        }
        try write(data, to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(CofreConstants.pairingRelativePath))
    }

    public static func write(_ data: Data, to destination: URL) throws {
        _ = try PairingFileValidator.validate(data)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: [.atomic, .completeFileProtection])
            try fm.replaceItemAt(destination, withItemAt: temporary)
        } catch CocoaError.fileNoSuchFile {
            try fm.moveItem(at: temporary, to: destination)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }
}
