import Foundation

public enum AccountState: String, Codable, Sendable { case ready, expired, demo }

public struct CofreAccount: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let isActive: Bool
    public let expiry: Date?
    public let state: AccountState
    public init(id: String, name: String, kind: String, isActive: Bool, expiry: Date?, state: AccountState) {
        self.id = id; self.name = name; self.kind = kind; self.isActive = isActive; self.expiry = expiry; self.state = state
    }
}

public final class AccountStore: @unchecked Sendable {
    public let accountsDirectory: URL
    private let now: () -> Date
    private let readSelected: () -> String?
    private let writeSelected: (String?) -> Void

    public init(directory: URL, now: @escaping () -> Date = Date.init,
                readSelected: @escaping () -> String? = { nil },
                writeSelected: @escaping (String?) -> Void = { _ in }) {
        accountsDirectory = directory.appendingPathComponent("accounts", isDirectory: true)
        self.now = now; self.readSelected = readSelected; self.writeSelected = writeSelected
    }

    public func list() -> [CofreAccount] {
        let selected = readSelected()
        let files = (try? FileManager.default.contentsOfDirectory(at: accountsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let id = (json["accountId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
            let name = (json["username"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            let microsoft = json["xuid"] != nil || json["xboxGamertag"] != nil || json["expiresAt"] != nil
            let expiry = (json["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let demo = (json["demo"] as? Bool == true) || (json["isDemoUser"] as? Bool == true) || (json["ownsJava"] as? Bool == false)
            let expired = expiry.map { $0 <= now() } ?? false
            return CofreAccount(id: id, name: name, kind: microsoft ? "Microsoft" : "Offline",
                                isActive: id == selected, expiry: expiry,
                                state: demo ? .demo : (expired ? .expired : .ready))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult public func remove(id: String) throws -> CofreAccount? {
        let account = list().first { $0.id == id }
        let file = accountsDirectory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        if readSelected() == id { writeSelected(list().first?.id) }
        return account
    }

    public func select(id: String?) {
        guard id == nil || list().contains(where: { $0.id == id }) else { return }
        writeSelected(id)
    }
}
