import Foundation

/// The shaders switch of Iris (Fabric/Quilt) or Oculus (Forge/NeoForge), kept in the game's own
/// `config/<mod>.properties`. The game owns it; Cofre only turns shaders off after a crash they caused.
public enum ShaderSwitch {
    static let files = ["iris.properties", "oculus.properties"]

    public static func isOn(in gameDirectory: URL) -> Bool {
        files.contains { value(of: "enableShaders", in: properties(gameDirectory, $0)) == "true" }
    }

    public static func turnOff(in gameDirectory: URL) throws {
        for name in files {
            let url = gameDirectory.appendingPathComponent("config").appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var lines = text.components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { key(of: $0) == "enableShaders" }) {
                lines[i] = "enableShaders=false"
            } else {
                lines.append("enableShaders=false")
            }
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A crash shaders likely caused: they're on, and the crash text names a shader mod or pack.
    public static func causedCrash(_ text: String, gameDirectory: URL) -> Bool {
        let t = text.lowercased()
        return isOn(in: gameDirectory) && ["iris", "oculus", "shaderpack", "shader pack", "shader"].contains { t.contains($0) }
    }

    private static func properties(_ gameDirectory: URL, _ name: String) -> String {
        (try? String(contentsOf: gameDirectory.appendingPathComponent("config").appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    private static func key(of line: String) -> String {
        line.split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func value(of key: String, in text: String) -> String? {
        text.components(separatedBy: "\n").first { self.key(of: $0) == key }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } }
    }
}
