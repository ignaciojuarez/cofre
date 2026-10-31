#if canImport(UIKit)
    import Foundation
    import CofreUI
    import CofreKit

    extension CofreBackendAdapter {
        private struct FabricLoader: Decodable { let loader: LoaderInfo }
        private struct LoaderInfo: Decodable {
            let version: String
            let stable: Bool?
        }

        private func requestData(urls: [URL]) async throws -> Data {
            var last: Error?
            for url in urls {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    request.setValue("Cofre/1.0", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw CofreBackendError.unavailable("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }
                    return data
                } catch { last = error }
            }
            throw last ?? CofreBackendError.unavailable("version catalog")
        }

        private func requestJSON<T: Decodable>(_ type: T.Type, urls: [URL]) async throws -> T {
            try JSONDecoder().decode(T.self, from: await requestData(urls: urls))
        }

        private func metadataURLs(_ original: URL, resource: Int) -> [URL] {
            air.instanceMetadataURLs(original, resource: resource)
        }

        public func gameVersions(_ kind: VersionKind) async throws -> [GameVersion] {
            let manifest = try VersionManifest.decode(
                await requestData(urls: metadataURLs(VersionManifest.url, resource: 0)))
            let entries: [VersionManifest.Entry]
            switch kind {
            case .release: entries = manifest.versions(.release)
            case .snapshot: entries = manifest.versions(.snapshot)
            case .old: entries = manifest.versions(.old)
            }
            return entries.map { GameVersion(id: $0.id, kind: kind) }
        }

        public func loaderVersions(loader: Loader, game: String) async throws -> [String] {
            switch loader {
            case .vanilla: return []
            case .unknown: throw CofreBackendError.unavailable("unknown loader")
            case .fabric, .quilt:
                let base =
                    loader == .quilt
                    ? "https://meta.quiltmc.org/v3/versions/loader" : "https://meta.fabricmc.net/v2/versions/loader"
                let url = URL(string: "\(base)/\(game)")!
                let rows: [FabricLoader] = try await requestJSON(
                    [FabricLoader].self,
                    urls: air.instanceMetadataURLs(url, resource: 3))
                return rows.map(\.loader.version)
            case .neoforge:
                return try await withCheckedThrowingContinuation { continuation in
                    air.neoForgeVersions(game) { versions, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: versions)
                        }
                    }
                }
            case .forge:
                // Forge's own Maven first, newest first; BMCLAPI (a community mirror Air uses) only if it fails.
                let xml = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml")!
                if let (data, response) = try? await URLSession.shared.data(from: xml),
                    (response as? HTTPURLResponse)?.statusCode == 200
                {
                    let versions = String(decoding: data, as: UTF8.self).split(separator: "<").compactMap { part in
                        part.hasPrefix("version>\(game)-")
                            ? part.split(separator: ">", maxSplits: 1).last.map { String($0.dropFirst(game.count + 1)) }
                            : nil
                    }
                    if !versions.isEmpty { return versions.reversed() }
                }
                let encoded = game.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? game
                struct Row: Decodable { let version: String }
                let rows: [Row] = try await requestJSON(
                    [Row].self, urls: [URL(string: "https://bmclapi2.bangbang93.com/forge/minecraft/\(encoded)")!])
                return rows.map(\.version)
            }
        }

        public func createInstance(name: String, version: String, loader: Loader) async throws -> InstanceSummary {
            try await createInstance(name: name, version: version, loader: loader, ownFolder: true, fabricAPI: false)
        }

        public func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool)
            async throws -> InstanceSummary
        {
            let d: NSDictionary
            do {
                d =
                    try
                    (air.createProfile(
                        name, version: version, loader: loader.rawValue, ownFolder: ownFolder, fabricAPI: fabricAPI)
                    as NSDictionary)
            } catch { throw error }
            let made = try instance(from: d)
            if loader == .fabric, fabricAPI { /* Air's installer adds Fabric API after profile JSON is written. */  }
            return made
        }

        nonisolated private func instance(from d: NSDictionary) throws -> InstanceSummary {
            guard let id = d["id"] as? String else { throw CofreBackendError.unavailable("instance creation") }
            let loader = Loader(rawValue: (d["loader"] as? String ?? "vanilla").lowercased()) ?? .unknown
            return InstanceSummary(
                id: id, name: d["name"] as? String ?? id, loader: loader,
                gameVersion: d["version"] as? String ?? "",
                loaderVersion: (d["loaderVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                ownFolder: d["ownFolder"] as? Bool ?? true,
                restartRequired: d["restartRequired"] as? Bool ?? false)
        }

        public func installLoader(instanceID: String, loader: Loader, version: String) async throws {
            guard !loaderInstallInProgress, launchingGameDirectory == nil else {
                throw CofreBackendError.unavailable("loader installation while Java is busy")
            }
            guard !air.jvmUsedInProcess() else { throw LaunchFailure.restartRequired }
            loaderInstallInProgress = true
            repairLibraries()
            if loader == .forge || loader == .neoforge {
                let name = loader.displayName
                do { try await ensureJIT() } catch {
                    loaderInstallInProgress = false
                    throw error
                }
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    let watchdog = AirWatchdog(idle: 120) {
                        Task { @MainActor in
                            self.recordJVMUse()
                            c.resume(throwing: self.air.jvmUsedInProcess() ? LaunchFailure.restartRequired :
                                LaunchFailure.unknown("Installing \(name) stopped responding. Close and reopen Cofre before trying again."))
                        }
                    }
                    air.installForgeLoader(
                        loader.rawValue, forProfile: instanceID, version: version,
                        progress: { p, message in
                            watchdog.poke()
                            NSLog("[Cofre] loader %.0f%% %@", p * 100, message)
                        }
                    ) { error in
                        Task { @MainActor in
                            self.loaderInstallInProgress = false
                            // Failed processors can consume Java too. Cached processors may use no JVM.
                            self.recordJVMUse()
                            guard watchdog.finish() else { return }
                            if let error { c.resume(throwing: error) } else { c.resume() }
                        }
                    }
                }
                return
            }
            defer { loaderInstallInProgress = false }
            guard loader == .fabric || loader == .quilt else {
                throw CofreBackendError.unavailable("loader installation")
            }
            let instances = air.instances()
            guard let row = instances.first(where: { ($0["id"] as? String) == instanceID }),
                let game = row["version"] as? String
            else { throw CofreBackendError.unavailable("instance") }
            let urls = air.loaderProfileURLs(loader.rawValue, game: game, version: version)
            let data = try await requestData(urls: urls)
            let json = try JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any] ?? [:]
            do {
                try air.saveLoaderProfile(json, forProfile: instanceID, loader: loader.rawValue, version: version)
            } catch { throw error }
            if loader == .fabric, row["fabricAPI"] as? Bool == true {
                let encodedGame = game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game
                let api = URL(
                    string:
                        "https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%5B%22\(encodedGame)%22%5D&loaders=%5B%22fabric%22%5D"
                )!
                if let data = try? await requestData(urls: [api]),
                    let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                    let files = rows.first?["files"] as? [[String: Any]],
                    let file = files.first(where: { ($0["primary"] as? Bool) == true }) ?? files.first
                {
                    await withCheckedContinuation { continuation in
                        let watchdog = AirWatchdog(idle: 120) { continuation.resume() }
                        air.installInstanceMod(file, forProfile: instanceID) { _ in
                            if watchdog.finish() { continuation.resume() }
                        }
                    }
                }
            }
        }

        public func duplicate(instanceID: String) async throws -> InstanceSummary {
            try await withCheckedThrowingContinuation { continuation in
                air.duplicateProfile(instanceID) { d, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    do { continuation.resume(returning: try self.instance(from: (d ?? [:]) as NSDictionary)) } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        public func delete(instanceID: String) async throws {
            do { try air.deleteProfile(instanceID) } catch { throw error }
        }

        public func export(instanceID: String, format: ExportFormat) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                air.exportProfile(instanceID, format: format.rawValue) { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: error ?? CofreBackendError.unavailable("instance export"))
                    }
                }
            }
        }
    }

    /// Fires `onTimeout` once if an Air callback goes `idle` seconds without progress.
    /// `finish()` returns true only for whichever of completion or timeout comes first.
    private final class AirWatchdog: @unchecked Sendable {
        private let lock = NSLock()
        private let idle: TimeInterval
        private let onTimeout: () -> Void
        private var finished = false
        private var timer: DispatchWorkItem?

        init(idle: TimeInterval, onTimeout: @escaping () -> Void) {
            self.idle = idle
            self.onTimeout = onTimeout
            poke()
        }

        func poke() {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            timer?.cancel()
            // Strong on purpose: the timer must fire even if Air drops its callbacks.
            let item = DispatchWorkItem { if self.finish() { self.onTimeout() } }
            timer = item
            DispatchQueue.global().asyncAfter(deadline: .now() + idle, execute: item)
        }

        func finish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return false }
            finished = true
            timer?.cancel()
            timer = nil
            return true
        }
    }
#endif
