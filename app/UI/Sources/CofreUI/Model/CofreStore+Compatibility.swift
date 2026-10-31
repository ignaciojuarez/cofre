#if canImport(UIKit)
    import Foundation
    import CofreKit

    // Renderer compatibility for Mods (badges, the Get warning) and Play (the "doesn't run here" sheet). The rules
    // are CofreKit's `ContentCompatibility`; this only picks the instance and its renderer.
    extension CofreStore {
        /// The renderer `instance` launches with, as the launch path decides it.
        func renderer(for instance: InstanceSummary) -> String {
            ModCompatibility.renderer(
                instanceSetting: (instancePreferences[instance.id]?.renderer ?? instance.renderer)?.rawValue,
                globalSetting: preferences.renderer.rawValue, gameVersion: instance.gameVersion,
                loader: instance.loader.rawValue, javaVersion: instance.javaVersion.flatMap(Int.init) ?? 21,
                metalMod: metalModEnabled(instance))
        }

        /// MetalUniversal is on in `instance`'s mods folder; previews without files use the loaded Mods list.
        public func metalModEnabled(_ instance: InstanceSummary) -> Bool {
            guard MetalMod.supports(gameVersion: instance.gameVersion, loader: instance.loader) else { return false }
            if let dir = gameDirectory(instance.id) { return MetalMod.isEnabled(in: dir) }
            return instance.id == modsInstance?.id
                && (installed[.mods] ?? []).contains { $0.enabled && $0.id.lowercased().hasPrefix(MetalMod.modID) }
        }

        /// "Use Metal": the pinned MetalUniversal jar into the mods folder (hash-checked), then Auto picks Metal.
        public func installMetalMod(_ instance: InstanceSummary) async {
            let pin = MetalMod.pin
            CofreBreadcrumb.log("metal-mod", details: instance.id)
            await run {
                if let dir = self.gameDirectory(instance.id) {
                    try await self.installPinned(pin, in: dir)
                } else if instance.id == self.modsInstance?.id {
                    self.installed[.mods, default: []].append(
                        InstalledItem(id: pin.file, name: "MetalUniversal", version: pin.version, enabled: true))
                }
                var p = self.preferences(for: instance.id)
                if !RendererPolicy.isMetal(p.renderer) && p.renderer != .auto {
                    p.renderer = .auto
                    self.save(p, instanceID: instance.id)
                }
                NSLog("[Cofre] metal mod installed instance=%@ renderer=%@", instance.id, self.renderer(for: instance))
            }
            if instance.id == modsInstance?.id, gameDirectory(instance.id) != nil { await loadInstalled(.mods) }
        }

        /// A preset or Metal file that isn't on Modrinth: a direct download checked against its pinned SHA-512.
        func installPinned(_ mod: CofrePreset.Mod, in gameDirectory: URL) async throws {
            guard let url = mod.url.flatMap(URL.init(string:)) else { throw CocoaError(.fileReadInvalidFileName) }
            _ = try await DownloadQueue.shared.download(
                url: url, destination: gameDirectory.appendingPathComponent("mods").appendingPathComponent(mod.file),
                title: "\(mod.slug) \(mod.version)", sha512: mod.sha512)
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

        func gameDirectory(_ instanceID: String) -> URL? {
            (try? instanceStore?.list())?.first { $0.id == instanceID }?.gameDirectory
        }
    }
#endif
