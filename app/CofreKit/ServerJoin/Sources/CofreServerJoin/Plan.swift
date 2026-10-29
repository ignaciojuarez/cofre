import Foundation
public struct MrpackFile: Codable, Equatable, Sendable { public let path: String; public let hashes: [String: String]; public let downloads: [URL]; public let fileSize: Int64?; public let env: [String: String]? }
public struct MrpackIndex: Codable, Equatable, Sendable { public let dependencies: [String: String]; public let files: [MrpackFile] }
public struct InstallEntry: Equatable, Sendable { public let path: String; public let sizeBytes: Int64; public let required: Bool; public let manual: Bool }
public struct InstallPlan: Equatable, Sendable { public let loader: LoaderRequirement; public let gameVersion: String; public let javaVersion: Int; public let entries: [InstallEntry]; public let totalDownloadSize: Int64; public let excluded: [String]; public let replacements: [IOSOverrides.Replacement] }
public enum InstallPlanner {
    public static func plan(card: ServerCard, index: MrpackIndex, environment: String = "client", ios: Bool = true) -> InstallPlan {
        let overrides = ios ? card.platformOverrides?.ios : nil
        let entries = index.files.compactMap { file -> InstallEntry? in
            if overrides?.exclude.contains(file.path) == true { return nil }
            if let env = file.env, env[environment] == "unsupported" { return nil }
            let manual = file.downloads.contains { $0.host?.contains("curseforge") == true } || file.path.lowercased().contains("curseforge")
            return InstallEntry(path: file.path, sizeBytes: file.fileSize ?? 0, required: true, manual: manual)
        }
        return InstallPlan(loader: card.loader, gameVersion: card.game.version, javaVersion: card.game.javaVersion, entries: entries, totalDownloadSize: entries.reduce(0) { $0 + $1.sizeBytes }, excluded: overrides?.exclude ?? [], replacements: overrides?.replace ?? [])
    }
}
