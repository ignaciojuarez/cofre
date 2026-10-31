import Foundation
import CofreKit

public struct RejoinIntent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case world, server }
    public let instanceID: String
    public let kind: Kind
    public let target: String
    public let displayName: String
    public let createdAt: Date
    public init(instanceID: String, kind: Kind, target: String, displayName: String, createdAt: Date = .now) {
        self.instanceID = instanceID; self.kind = kind; self.target = target; self.displayName = displayName; self.createdAt = createdAt
    }
}

public enum RejoinIntentStore {
    private static var key: String { PreferenceKey.rejoinIntent.rawValue }
    public static func load(defaults: UserDefaults = .standard, now: Date = .now) -> RejoinIntent? {
        guard let data = defaults.data(forKey: key), let intent = try? JSONDecoder().decode(RejoinIntent.self, from: data), now.timeIntervalSince(intent.createdAt) < 600 else {
            if defaults.data(forKey: key) != nil { defaults.removeObject(forKey: key) }
            return nil
        }
        return intent
    }
    public static func save(_ intent: RejoinIntent, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        defaults.set(data, forKey: key)
        NSLog("[Cofre] rejoin intent instance=%@ kind=%@ target=%@", intent.instanceID, intent.kind.rawValue, intent.target)
    }
    public static func clear(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

public enum RejoinDetector {
    public static func server(in log: String) -> String? {
        let pattern = #"Connecting to ([^,]+),\s*(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for line in log.split(whereSeparator: \.isNewline).reversed() {
            let ns = String(line) as NSString
            if let m = regex?.firstMatch(in: ns as String, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                let host = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let port = ns.substring(with: m.range(at: 2))
                if String(line).contains("Connecting to ") { return "\(host):\(port)" }
            }
        }
        return nil
    }
    public static func world(in gameDirectory: URL, since: Date, fileManager: FileManager = .default) -> URL? {
        let saves = gameDirectory.appendingPathComponent("saves", isDirectory: true)
        guard let folders = try? fileManager.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        return folders.compactMap { folder -> (URL, Date)? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let level = folder.appendingPathComponent("level.dat")
            guard let date = try? level.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date >= since else { return nil }
            return (folder, date)
        }.max { $0.1 < $1.1 }?.0
    }
}
