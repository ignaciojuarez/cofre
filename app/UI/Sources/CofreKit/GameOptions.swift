import Foundation

/// Starting view distances in options.txt. Air's engine fills a new options.txt with renderDistance:2 and
/// simulationDistance:5, so every new world looked like fog two chunks out. Air only fills keys that are
/// missing, so Cofre writes playable distances first; after that the game owns them.
public enum GameOptions {
    /// What Air writes when the keys are missing.
    static let engineDefaults = ["renderDistance": "2", "simulationDistance": "5"]

    /// Distances for this device: devices under 6 GB get less, since chunks cost native graphics memory too.
    public static func distances(physicalMB: Int) -> [String: String] {
        physicalMB >= 6000
            ? ["renderDistance": "10", "simulationDistance": "8"]
            : ["renderDistance": "6", "simulationDistance": "5"]
    }

    /// Filled only when missing: the game's 120/260 FPS cap on a 60 Hz screen only adds heat (an iPad mini hit
    /// "serious" thermal state on Metal), and the menu blur cost a +650 MB spike on a 4 GB iPad.
    static func comfort(displayHz: Int) -> [String: String] {
        ["maxFps": String(max(30, displayHz)), "menuBackgroundBlurriness": "0"]
    }

    /// Fills missing distances and comfort settings. With `replacingEngineDefaults`, also replaces distances equal to
    /// Air's defaults (used once per instance, for instances Air already launched). Returns whether the file changed.
    @discardableResult
    public static func seedDistances(
        in gameDirectory: URL, physicalMB: Int, displayHz: Int = 60, replacingEngineDefaults: Bool
    ) throws -> Bool {
        let url = gameDirectory.appendingPathComponent("options.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        var changed = false
        let values = distances(physicalMB: physicalMB).merging(comfort(displayHz: displayHz)) { a, _ in a }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
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

    /// Minecraft forces `preferredGraphicsBackend:"opengl"` after a startup that didn't finish (any crash before the
    /// first world). On iOS a Metal instance then starts on ANGLE OpenGL and shows a black screen, so a Metal launch
    /// removes the forced value. Returns whether the file changed.
    @discardableResult
    public static func clearForcedOpenGL(in gameDirectory: URL) throws -> Bool {
        let url = gameDirectory.appendingPathComponent("options.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: "\n")
        let kept = lines.filter { $0.trimmingCharacters(in: .whitespaces) != "preferredGraphicsBackend:\"opengl\"" }
        guard kept.count != lines.count else { return false }
        try kept.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    /// Fills the first-create settings for a preset without replacing an existing player's choices.
    @discardableResult
    public static func seedPreset(
        _ options: CofrePreset.FirstCreateOptions, in gameDirectory: URL, physicalMB: Int
    ) throws -> Bool {
        let url = gameDirectory.appendingPathComponent("options.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let distances = distances(physicalMB: physicalMB)
        let values: [String: String] = [
            "renderDistance": distances["renderDistance"] ?? String(options.renderDistance),
            "simulationDistance": distances["simulationDistance"] ?? String(options.simulationDistance),
            "entityDistanceScaling": String(options.entityDistanceScaling),
            "mipmapLevels": String(options.mipmapLevels),
            "menuBackgroundBlurriness": String(options.menuBackgroundBlurriness),
            "touchscreen": String(options.touchscreen),
            "maxFps": String(options.maxFps),
            "enableVsync": String(options.enableVsync),
        ]
        var changed = false
        for key in values.keys.sorted() where !lines.contains(where: { $0.hasPrefix(key + ":") }) {
            let end = lines.last == "" ? lines.count - 1 : lines.count
            lines.insert("\(key):\(values[key]!)", at: end)
            changed = true
        }
        guard changed else { return false }
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}
