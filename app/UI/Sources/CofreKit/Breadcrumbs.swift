import Foundation

public enum CofreBreadcrumb {
    public static func line(action: String, details: String = "") -> String {
        let suffix = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? "[Cofre] action \(action)" : "[Cofre] action \(action) \(suffix)"
    }
    public static func log(_ action: String, details: String = "") { NSLog("%@", line(action: action, details: details)) }
}

public enum OptionsDiff {
    public struct Change: Equatable, Sendable { public let key: String, old: String?, new: String }

    /// Settings the player changed in game: options.txt at launch against options.txt now.
    public static func changed(before: String, after: String) -> [Change] {
        func parse(_ text: String) -> [String: String] {
            text.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { result[parts[0]] = parts[1] }
            }
        }
        // Without a launch snapshot every line would look changed.
        guard !before.isEmpty else { return [] }
        let old = parse(before), new = parse(after)
        return Set(old.keys).union(new.keys).sorted().compactMap { key in
            guard old[key] != new[key], let value = new[key] else { return nil }
            return Change(key: key, old: old[key], new: value)
        }
    }

    public static func changes(before: String, after: String) -> [String] {
        changed(before: before, after: after).map { "[Cofre] options changed \($0.key): \($0.old ?? "<unset>") → \($0.new)" }
    }

    /// Settings whose change makes Minecraft reload every texture (where Metal can crash), by their menu name.
    public static let reloading = [
        "graphicsPreset": "Graphics", "graphicsMode": "Graphics", "mipmapLevels": "Mipmap levels",
        "resourcePacks": "Resource packs", "lang": "Language", "forceUnicodeFont": "Force Unicode font",
        "textureFiltering": "Texture filtering", "maxAnisotropyBit": "Anisotropic filtering",
    ]

    /// The reloading settings among `changes`, by menu name, once each.
    public static func reloadingNames(_ changes: [Change]) -> [String] {
        changes.compactMap { reloading[$0.key] }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
