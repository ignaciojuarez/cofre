import Foundation

/// A game that reached its first frame and may still be running when Cofre is relaunched.
public struct GameSession: Codable, Equatable, Sendable {
    public let instanceID: String
    public let startedAt: Date

    public init(instanceID: String, startedAt: Date = .now) {
        self.instanceID = instanceID
        self.startedAt = startedAt
    }
}

/// Persists the one game session that Cofre owns. A marker left at app start means
/// iOS (or the user) ended the previous process before Cofre saw the game exit.
public enum GameSessionMarker {
    private static let key = PreferenceKey.gameSession.rawValue

    public static func begin(instanceID: String, at date: Date = .now, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(GameSession(instanceID: instanceID, startedAt: date)) else { return }
        defaults.set(data, forKey: key)
    }

    public static func consume(defaults: UserDefaults = .standard) -> GameSession? {
        defer { defaults.removeObject(forKey: key) }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GameSession.self, from: data)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
