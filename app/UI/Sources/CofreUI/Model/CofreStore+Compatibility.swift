#if canImport(UIKit)
    import Foundation
    import CofreKit

    // Renderer compatibility for Mods (badges, the Get warning) and Play (the "doesn't run here" sheet). The rules
    // are CofreKit's `ContentCompatibility`; this only picks the instance and its renderer.
    extension CofreStore {
        /// The renderer `instance` launches with, as the launch path decides it.
        func renderer(for instance: InstanceSummary) -> String {
            ModCompatibility.renderer(
                instanceSetting: instancePreferences[instance.id]?.renderer ?? instance.renderer,
                globalSetting: preferences.renderer, gameVersion: instance.gameVersion,
                loader: instance.loader.rawValue, javaVersion: instance.javaVersion.flatMap(Int.init) ?? 21)
        }

        /// A search row, mod page or Get for the Mods instance (or `instance`).
        public func compatibilityIssue(id: String, name: String, kind: ContentKind, instance: InstanceSummary? = nil)
            -> ModCompatibilityIssue?
        {
            guard let i = instance ?? modsInstance else { return nil }
            return ModCompatibility.issue(
                id: id, name: name, kind: kind, gameVersion: i.gameVersion, renderer: renderer(for: i))
        }

        public func compatibilityIssue(for item: InstalledItem, instance: InstanceSummary? = nil)
            -> ModCompatibilityIssue?
        {
            guard item.kind == .mods || item.kind == .shaders else { return nil }
            return compatibilityIssue(
                id: item.projectID ?? item.id, name: item.name, kind: item.kind, instance: instance)
        }

        /// What won't run when `instance` starts. Read from its folder, so it holds for any instance, not only the
        /// one Mods has loaded; previews without files use the loaded list.
        func playIssues(_ instance: InstanceSummary) -> [ModCompatibilityIssue] {
            let renderer = renderer(for: instance)
            if let dir = gameDirectory(instance.id) {
                return ContentCompatibility.playIssues(
                    gameDirectory: dir, gameVersion: instance.gameVersion, renderer: renderer,
                    manifest: ModCompatibility.manifest)
            }
            let items = (installed[.mods] ?? []) + (installed[.shaders] ?? [])
            guard
                case .warn(let issues) = ModCompatibilityChecker.decision(
                    items: items, gameVersion: instance.gameVersion, renderer: renderer)
            else { return [] }
            return issues
        }

        /// "Turn off and play": the flagged mods, and shaders through the shader mod's own switch. The game isn't
        /// running yet, so writing its config is safe.
        func turnOffForPlay(_ issues: [ModCompatibilityIssue], instanceID: String) {
            CofreBreadcrumb.log("compat-off", details: issues.map(\.modName).joined(separator: ","))
            if let dir = gameDirectory(instanceID) {
                do {
                    try ContentCompatibility.turnOff(issues, gameDirectory: dir)
                    NSLog("[Cofre] compat turned off instance=%@ items=%ld", instanceID, issues.count)
                } catch { lastError = error.localizedDescription }
                if instanceID == modsInstance?.id {
                    Task { for kind in [ContentKind.mods, .shaders] { await loadInstalled(kind) } }
                }
                return
            }
            for item in (installed[.mods] ?? [])
            where item.enabled
                && issues.contains(where: { $0.modID == (item.projectID ?? item.id) })
            {
                setEnabled(false, item: item)
            }
        }

        private func gameDirectory(_ instanceID: String) -> URL? {
            (try? instanceStore?.list())?.first { $0.id == instanceID }?.gameDirectory
        }
    }
#endif
