import Foundation

/// Forge's and NeoForge's own `config/fml.toml`. Their early loading window needs desktop LWJGL classes that
/// Air's iOS LWJGL doesn't give it, so the game exits before it starts (NoClassDefFoundError:
/// org/lwjgl/system/Struct). Cofre turns that window off before launch; the game's own loading screen follows.
public enum FMLConfig {
    public static func disableEarlyWindow(in gameDirectory: URL) throws {
        let url = gameDirectory.appendingPathComponent("config/fml.toml")
        var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n") ?? []
        let setting = "earlyWindowControl = false"
        if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("earlyWindowControl") }) {
            guard lines[i] != setting else { return }
            lines[i] = setting
        } else {
            // FML fills in every other setting with its defaults when it loads the file.
            lines.append(setting)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
