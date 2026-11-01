import Foundation

/// The dependency edge Cofre knows for one installed mod. `id` is normally a project ID, but jar metadata may only
/// provide a loader mod ID, so callers can also provide aliases on the owning node.
public struct ModDependency: Hashable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var required: Bool

    public init(id: String, name: String? = nil, required: Bool = true) {
        self.id = id
        self.name = name ?? id
        self.required = required
    }
}

public struct InstalledModNode: Hashable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var aliases: [String]
    public var dependencies: [ModDependency]
    public var installedDirectly: Bool
    public var protectedFromRemoval: Bool

    public init(
        id: String, name: String, aliases: [String] = [], dependencies: [ModDependency] = [],
        installedDirectly: Bool = true, protectedFromRemoval: Bool = false
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.dependencies = dependencies
        self.installedDirectly = installedDirectly
        self.protectedFromRemoval = protectedFromRemoval
    }

    fileprivate var keys: Set<String> {
        Set(([id] + aliases).map(Self.key))
    }

    fileprivate static func key(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Chooses dependency jars that can disappear with a removed mod. Disabled jars still count as dependents: the next
/// launch would load them if enabled, so a shared dependency must stay.
public enum ModRemovalPlanner {
    public static func options(removing rootID: String, from nodes: [InstalledModNode]) -> [InstalledModNode] {
        guard let root = nodes.first(where: { $0.id == rootID }) else { return [] }
        var removed: Set<String> = [root.id]
        var offered: [InstalledModNode] = []
        var queue = [root]
        while let parent = queue.first {
            queue.removeFirst()
            for dependency in parent.dependencies where dependency.required {
                let candidate = nodes.first { $0.id != root.id && $0.keys.contains(Self.key(dependency.id)) }
                guard let candidate, !removed.contains(candidate.id), !candidate.installedDirectly,
                    !candidate.protectedFromRemoval
                else { continue }
                let stillNeeded = nodes.contains { node in
                    !removed.contains(node.id)
                        && node.dependencies.contains { $0.required && candidate.keys.contains(Self.key($0.id)) }
                }
                guard !stillNeeded else { continue }
                removed.insert(candidate.id)
                offered.append(candidate)
                queue.append(candidate)
            }
        }
        return offered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Applies a user's checkbox selection without deleting a dependency that a kept mod still needs. Recursive
    /// options are presented together, so unchecking a parent must also keep the exclusive dependencies below it.
    public static func selected(
        removing rootID: String, candidates: Set<String>, from nodes: [InstalledModNode]
    ) -> [InstalledModNode] {
        let offered = Set(options(removing: rootID, from: nodes).map(\.id))
        var removed = Set([rootID]).union(candidates.intersection(offered))
        var changed = true
        while changed {
            changed = false
            for node in nodes where !removed.contains(node.id) {
                for dependency in node.dependencies where dependency.required {
                    guard let candidate = nodes.first(where: { $0.keys.contains(Self.key(dependency.id)) }),
                        removed.contains(candidate.id), candidate.id != rootID
                    else { continue }
                    removed.remove(candidate.id)
                    changed = true
                }
            }
        }
        return nodes.filter { removed.contains($0.id) && $0.id != rootID }
    }

    private static func key(_ value: String) -> String {
        InstalledModNode.key(value)
    }
}
