#if canImport(UIKit)
    import Foundation
    import CofreKit

    extension CofreBackendAdapter {
        /// Stops a launch whose game files can't fit, before Air starts downloading them. Unknown sizes
        /// (offline, an unlisted version) let the launch go on: Air's own download error still applies.
        func checkDiskBeforeLaunch(_ instance: Instance, root: URL) async throws {
            let estimate = try? await VersionDownloads.estimate(version: instance.gameVersion, root: root) { url in
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                return try await URLSession.shared.data(for: request).0
            }
            guard let estimate else {
                NSLog("[Cofre] downloads preflight version=%@ skipped", instance.gameVersion)
                return
            }
            let check = DiskPreflight.check(downloadBytes: estimate.totalBytes, at: root)
            NSLog(
                "[Cofre] downloads preflight version=%@ download=%lld free=%lld ok=%d",
                instance.gameVersion, estimate.totalBytes, check.freeBytes, check.hasRoom)
            guard check.hasRoom else { throw LaunchFailure.downloadFailed(check.summary) }
        }
    }
#endif
