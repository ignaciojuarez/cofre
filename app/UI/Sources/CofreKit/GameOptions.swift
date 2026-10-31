import Foundation

/// Starting view distances in options.txt. Air's engine fills a new options.txt with renderDistance:2 and
/// simulationDistance:5, so every new world looked like fog two chunks out. Air only fills keys that are
/// missing, so Cofre writes playable distances first; after that the game owns them.
public enum GameOptions {
    /// What Air writes when the keys are missing.
    static let engineDefaults = ["renderDistance": "2", "simulationDistance": "5"]

    /// Distances for this device: 4 GB iPads and older iPhones get less, since chunks cost heap.
    public static func distances(physicalMB: Int) -> [String: String] {
        physicalMB >= 6000
            ? ["renderDistance": "10", "simulationDistance": "8"]
            : ["renderDistance": "8", "simulationDistance": "6"]
    }

    /// Fills missing distances. With `replacingEngineDefaults`, also replaces values equal to Air's defaults
    /// (used once per instance, for instances Air already launched). Returns whether the file changed.
    @discardableResult
    public static func seedDistances(
        in gameDirectory: URL, physicalMB: Int, replacingEngineDefaults: Bool
    ) throws -> Bool {
        let url = gameDirectory.appendingPathComponent("options.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        var changed = false
        for (key, value) in distances(physicalMB: physicalMB).sorted(by: { $0.key < $1.key }) {
            if let i = lines.firstIndex(where: { $0.hasPrefix(key + ":") }) {
                guard replacingEngineDefaults, lines[i] == "\(key):\(engineDefaults[key] ?? "")" else { continue }
                lines[i] = "\(key):\(value)"
            } else {
                let end = lines.last == "" ? lines.count - 1 : lines.count
                lines.insert("\(key):\(value)", at: end)
            }
            changed = true
        }
        guard changed else { return false }
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}
