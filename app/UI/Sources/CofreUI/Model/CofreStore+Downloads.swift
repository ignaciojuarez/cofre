#if canImport(UIKit)
    import Foundation

    extension CofreStore {
        /// Reinstalls the instance's loader at `version`. The engine writes the new version id and `loaderVersion`
        /// into the profile; failures (Java already ran, no network) land in `lastError` and change nothing.
        public func changeLoaderVersion(_ id: String, to version: String) async {
            guard let inst = instances.first(where: { $0.id == id }), inst.loader != .vanilla,
                inst.loaderVersion != version
            else { return }
            NSLog("[Cofre] loader change instance=%@ loader=%@ version=%@", id, inst.loader.rawValue, version)
            var changed = false
            await run {
                try await self.backend.installLoader(instanceID: id, loader: inst.loader, version: version)
                changed = true
            }
            NSLog("[Cofre] loader change done=%d", changed)
            await refreshLibrary()
            // A backend without the instance store keeps its own list; show the choice it accepted.
            if changed, instanceStore == nil, let i = instances.firstIndex(where: { $0.id == id }) {
                instances[i].loaderVersion = version
            }
        }
    }
#endif
