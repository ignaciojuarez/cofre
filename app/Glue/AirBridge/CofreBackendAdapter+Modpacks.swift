#if canImport(UIKit)
    import Foundation
    import CofreUI
    import CofreKit

    extension CofreBackendAdapter {
        /// Imports a `.mrpack`, CurseForge or MultiMC ZIP, a Cofre instance export, or a link to one, as a new
        /// instance. Cofre stages and checks the file; Air downloads the mods and installs the loader. A failed import,
        /// including one whose loader didn't install, leaves nothing behind. Packs always make a new instance, so
        /// `instanceID` is unused.
        public func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error> {
            AsyncThrowingStream { continuation in
                let task = Task { @MainActor in
                    var title = url.deletingPathExtension().lastPathComponent
                    var stages: [InstallProgress.Stage] = [
                        .init(title: "Pack", state: .checking), .init(title: "Mods and loader", state: .unknown),
                        .init(title: "Instance", state: .unknown),
                    ]
                    func send(_ fraction: Double, _ detail: String? = nil) {
                        continuation.yield(
                            InstallProgress(title: title, fraction: fraction, detail: detail, stages: stages))
                    }
                    var staged: URL?
                    defer { staged.map { ModpackImport.discard($0) } }
                    do {
                        send(0)
                        let file: URL
                        if url.isFileURL {
                            file = try ModpackImport.receive(url)
                        } else {
                            file = try await downloadPack(url) { send($0 * 0.1, "Downloading the pack") }
                        }
                        staged = file
                        let pack = try ModpackImport.inspect(file)
                        title = pack.name ?? title
                        NSLog(
                            "[Cofre] pack import kind=%@ mc=%@ loader=%@ downloads=%ld bytes=%lld",
                            pack.kind.rawValue, pack.gameVersion ?? "?", pack.loader.rawValue, pack.downloads,
                            pack.unpackedBytes + pack.downloadBytes)
                        let space = DiskPreflight.check(
                            downloadBytes: pack.unpackedBytes + pack.downloadBytes, at: file)
                        guard space.hasRoom else { throw packError(space.summary) }
                        stages[0].state = .ready
                        stages[0].detail = [pack.gameVersion, pack.loader == .vanilla ? nil : pack.loader.displayName]
                            .compactMap { $0 }.joined(separator: " · ")
                        stages[1].state = .checking
                        send(0.1)
                        let made: String
                        if pack.kind == .cofreInstance {
                            guard let store = instances else { throw packError("Instances aren't available yet.") }
                            made = try store.import(file).id
                        } else {
                            made = try await importWithAir(file) { send(0.1 + $0 * 0.89, $1) }
                        }
                        stages[1].state = .ready
                        stages[2].state = .ready
                        NSLog("[Cofre] pack import done instance=%@", made)
                        send(1)
                        continuation.finish()
                    } catch {
                        NSLog("[Cofre] pack import failed: %@", error.localizedDescription)
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        /// Runs Air's importer in `custom_gamedir`, rolling back on failure or crash, and returns the new instance's id.
        /// Air keeps an instance whose loader failed to install; Cofre removes it, since it can't launch.
        func importWithAir(_ file: URL, progress: @escaping (Double, String?) -> Void) async throws -> String {
            guard let packs = Self.modpackDirectory else { throw packError("The game folder is unavailable.") }
            let fm = FileManager.default
            try fm.createDirectory(at: packs, withIntermediateDirectories: true)
            let before = Set(air.instances().compactMap { $0["id"] as? String })
            let versions = instances?.root.appendingPathComponent("versions", isDirectory: true)
            let versionsBefore = Set(versions.flatMap { try? fm.contentsOfDirectory(atPath: $0.path) } ?? [])
            ModpackImport.cleanupAbandonedImport(in: packs)
            try ModpackImport.markImportStarted(in: packs)
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                air.importPack(
                    file,
                    progress: { fraction, message in
                        Task { @MainActor in progress(min(max(fraction, 0), 0.99), message) }
                    },
                    completion: { error in
                        // A failed import is rolled back now; a crash is rolled back at the next launch.
                        if error != nil {
                            ModpackImport.cleanupAbandonedImport(in: packs)
                        } else {
                            ModpackImport.markImportFinished(in: packs)
                        }
                        if let error { done.resume(throwing: error) } else { done.resume() }
                    })
            }
            guard let id = air.instances().compactMap({ $0["id"] as? String }).first(where: { !before.contains($0) })
            else {
                throw packError("The pack finished importing but made no instance.")
            }
            guard let store = instances, let instance = try store.list().first(where: { $0.id == id }) else {
                return id
            }
            guard
                instance.loader.isInstalled(
                    in: instance.versionID, root: store.root, minecraftVersion: instance.gameVersion)
            else {
                NSLog(
                    "[Cofre] pack import rollback instance=%@ reason=loader %@ %@", id, instance.loader.rawValue,
                    instance.loaderVersion ?? "?")
                try? store.remove(id)
                if let version = instance.versionID, !versionsBefore.contains(version), let versions {
                    try? fm.removeItem(at: versions.appendingPathComponent(version, isDirectory: true))
                }
                throw packError(
                    "\(instance.loader.displayName) \(instance.loaderVersion ?? "") didn't install, so the pack wasn't kept. Check your connection and try again."
                )
            }
            return id
        }

        /// Downloads the pack a link points to: a Modrinth modpack page (newest version, or the one in the link) or
        /// a direct `.mrpack`/`.zip` link.
        private func downloadPack(_ link: URL, progress: (Double) -> Void) async throws -> URL {
            let source: (url: URL, name: String, size: Int64?, sha1: String?, sha512: String?)
            switch try ModpackImport.link(link) {
            case .file(let url):
                source = (url, url.lastPathComponent, nil, nil, nil)
            case .modrinth(let project, let version):
                let versions = try await Modrinth().versions(projectID: project)
                guard let file = ModpackImport.packFile(in: versions, version: version), let url = file.url else {
                    throw packError("That Modrinth page has no .mrpack to download.")
                }
                source = (url, file.filename, file.size, file.hashes["sha1"], file.hashes["sha512"])
            }
            NSLog("[Cofre] pack import link host=%@", source.url.host() ?? "?")
            let destination = try ModpackImport.stagingFile(named: source.name)
            progress(0.5)
            do {
                return try await DownloadQueue.shared.download(
                    url: source.url, destination: destination, title: source.name, totalBytes: source.size,
                    sha1: source.sha1, sha512: source.sha512)
            } catch {
                ModpackImport.discard(destination)
                throw error
            }
        }

        private func packError(_ message: String) -> NSError {
            NSError(domain: "CofreModpacks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
#endif
