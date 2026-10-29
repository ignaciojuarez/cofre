import Foundation

public struct UpdateDiff: Equatable, Sendable {
    public let added: [String]
    public let updated: [String]
    public let removed: [String]
    public let downloadSize: Int64
    public let preservedUserOptional: [String]
}
public enum UpdateDiffer {
    public static func diff(old: MrpackIndex, new: MrpackIndex, userOptional: Set<String> = []) -> UpdateDiff {
        let a = Dictionary(uniqueKeysWithValues: old.files.map { ($0.path, $0) })
        let b = Dictionary(uniqueKeysWithValues: new.files.map { ($0.path, $0) })
        let added = b.keys.filter { a[$0] == nil }.sorted()
        let removed = a.keys.filter { b[$0] == nil && !userOptional.contains($0) }.sorted()
        let updated = b.keys.filter {
            if let old = a[$0], let next = b[$0] { return old.hashes != next.hashes }
            return false
        }.sorted()
        return UpdateDiff(
            added: added, updated: updated, removed: removed,
            downloadSize: (added + updated).compactMap { b[$0]?.fileSize }.reduce(0, +),
            preservedUserOptional: userOptional.filter { a[$0] != nil }.sorted())
    }
}
