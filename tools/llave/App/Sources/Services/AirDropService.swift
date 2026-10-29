import AppKit
import Foundation

public protocol AirDropServiceProtocol: AnyObject, Sendable {
    @MainActor func sendViaAirDrop(fileURL: URL) -> Bool
    @MainActor func saveToDesktop(fileURL: URL) throws -> URL
}

public final class AirDropService: AirDropServiceProtocol, @unchecked Sendable {
    public init() {}

    @MainActor
    public func sendViaAirDrop(fileURL: URL) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            return false
        }
        guard service.canPerform(withItems: [fileURL]) else {
            return false
        }
        service.perform(withItems: [fileURL])
        return true
    }

    @MainActor
    public func saveToDesktop(fileURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let destination = desktop.appendingPathComponent(fileURL.lastPathComponent)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: fileURL, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }
}
