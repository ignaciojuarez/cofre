#if canImport(UIKit)
    import CofreKit
    import Foundation

    extension CofreStore {
        public func ensureProjectSummary(for item: InstalledItem) {
            guard let id = item.projectID, !results.contains(where: { $0.id == id }) else { return }
            let source = item.projectSource ?? .modrinth
            results.append(
                ProjectSummary(
                    id: id, title: item.name, author: "", summary: "", iconURL: item.iconURL,
                    downloads: 0, loaders: modsInstance.map { [$0.loader] } ?? [], fits: true, installed: true,
                    source: source,
                    pageURL: source == .modrinth ? URL(string: "https://modrinth.com/project/\(id)") : nil))
        }

        public func projectSummary(for item: InstalledItem) -> ProjectSummary? {
            ensureProjectSummary(for: item)
            return item.projectID.flatMap { id in results.first { $0.id == id } }
        }

        public func removalOptions(for item: InstalledItem) -> [InstalledItem] {
            guard item.kind == .mods else { return [] }
            let nodes = removalNodes()
            let options = ModRemovalPlanner.options(removing: item.id, from: nodes)
            return options.compactMap { node in installed[.mods]?.first { $0.id == node.id } }
        }

        public func removalItems(for item: InstalledItem, selectedIDs: Set<String>) -> [InstalledItem] {
            guard item.kind == .mods else { return [] }
            let selected = ModRemovalPlanner.selected(removing: item.id, candidates: selectedIDs, from: removalNodes())
            return selected.compactMap { node in installed[.mods]?.first { $0.id == node.id } }
        }

        private func removalNodes() -> [InstalledModNode] {
            (installed[.mods] ?? []).map {
                InstalledModNode(
                    id: $0.id, name: $0.name,
                    aliases: [$0.projectID, $0.modID, $0.name].compactMap { $0 },
                    dependencies: $0.dependencies, installedDirectly: $0.installedDirectly,
                    protectedFromRemoval: $0.protectedFromRemoval)
            }
        }

        public func deleteItems(_ items: [InstalledItem]) {
            guard let instanceID = modsInstance?.id else { return }
            var seen = Set<String>()
            let unique = items.filter { seen.insert($0.id).inserted }
            for item in unique { installed[item.kind]?.removeAll { $0.id == item.id } }
            Task {
                for item in unique { await run { try await self.backend.delete(item, instanceID: instanceID) } }
            }
        }
    }
#endif
