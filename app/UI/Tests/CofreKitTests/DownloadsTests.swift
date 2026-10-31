import Foundation
import XCTest

@testable import CofreKit

final class DownloadsTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let manifest = Data(
        """
        {"latest":{"release":"1.21.4","snapshot":"25w02a"},"versions":[
          {"id":"25w02a","type":"snapshot","url":"https://piston-meta.mojang.com/v1/packages/a/25w02a.json"},
          {"id":"1.21.4","type":"release","url":"https://piston-meta.mojang.com/v1/packages/b/1.21.4.json"},
          {"id":"1.21.1","type":"release","url":"https://piston-meta.mojang.com/v1/packages/c/1.21.1.json"},
          {"id":"b1.7.3","type":"old_beta","url":"https://piston-meta.mojang.com/v1/packages/d/b1.7.3.json"},
          {"id":"a1.2.6","type":"old_alpha","url":"https://piston-meta.mojang.com/v1/packages/e/a1.2.6.json"}]}
        """.utf8)
    private let versionJSON = Data(
        """
        {"id":"1.21.4","assetIndex":{"id":"19","totalSize":400000000},
         "downloads":{"client":{"size":28000000,"url":"https://x/client.jar"}},
         "libraries":[
           {"name":"a:a:1","downloads":{"artifact":{"path":"a/a/1/a-1.jar","size":1000}}},
           {"name":"b:b:1","downloads":{"artifact":{"path":"b/b/1/b-1.jar","size":2000}}},
           {"name":"natives-only","downloads":{"classifiers":{}}}]}
        """.utf8)

    func testManifestSplitsReleasesSnapshotsAndOld() throws {
        let m = try VersionManifest.decode(manifest)
        XCTAssertEqual(m.versions(.release).map(\.id), ["1.21.4", "1.21.1"])
        XCTAssertEqual(m.versions(.snapshot).map(\.id), ["25w02a"])
        XCTAssertEqual(m.versions(.old).map(\.id), ["b1.7.3", "a1.2.6"])
        XCTAssertEqual(m.latest?.release, "1.21.4")
        XCTAssertEqual(m.entry("1.21.1")?.url?.lastPathComponent, "1.21.1.json")
    }

    func testMissingCountsOnlyFilesNotYetDownloaded() throws {
        var d = try VersionDownloads.missing(json: versionJSON, id: "1.21.4", root: root)
        XCTAssertEqual(d, VersionDownloads(clientBytes: 28_000_000, libraryBytes: 3000, assetBytes: 400_000_000))
        for path in ["versions/1.21.4/1.21.4.jar", "libraries/a/a/1/a-1.jar", "assets/indexes/19.json"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        d = try VersionDownloads.missing(json: versionJSON, id: "1.21.4", root: root)
        XCTAssertEqual(d.totalBytes, 2000)
    }

    func testEstimatePrefersLocalJSONAndFallsBackToManifest() async throws {
        var asked: [URL] = []
        let fetched = try await VersionDownloads.estimate(version: "1.21.4", root: root) { url in
            asked.append(url)
            return url == VersionManifest.url ? self.manifest : self.versionJSON
        }
        XCTAssertEqual(asked.map(\.lastPathComponent), ["version_manifest_v2.json", "1.21.4.json"])
        XCTAssertEqual(fetched.totalBytes, 428_003_000)

        let local = root.appendingPathComponent("versions/1.21.4/1.21.4.json")
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try versionJSON.write(to: local)
        asked = []
        _ = try await VersionDownloads.estimate(version: "1.21.4", root: root) {
            asked.append($0)
            return Data()
        }
        XCTAssertTrue(asked.isEmpty)
    }

    func testDiskPreflightNeedsDownloadPlusMargin() {
        let mb: Int64 = 1024 * 1024
        let fits = DiskPreflight(downloadBytes: 400 * mb, freeBytes: 18_000 * mb)
        XCTAssertTrue(fits.hasRoom)
        XCTAssertTrue(fits.summary.hasPrefix("Downloads "))
        let tight = DiskPreflight(downloadBytes: 400 * mb, freeBytes: 450 * mb)
        XCTAssertEqual(tight.needBytes, 400 * mb + DiskPreflight.margin)
        XCTAssertFalse(tight.hasRoom)
        XCTAssertTrue(tight.summary.hasPrefix("Not enough space"))
        XCTAssertTrue(DiskPreflight(downloadBytes: 0, freeBytes: 0).hasRoom)
        XCTAssertNotNil(DiskPreflight.freeBytes(at: root.appendingPathComponent("not/yet/here")))
    }

    func testCellularAskOnlyAboveLimitOnCellular() {
        let big = DownloadQueue.cellularAskBytes + 1
        XCTAssertTrue(DownloadQueue.asksOnCellular(bytes: big, onCellular: true, allowCellular: false))
        XCTAssertFalse(DownloadQueue.asksOnCellular(bytes: big, onCellular: false, allowCellular: false))
        XCTAssertFalse(DownloadQueue.asksOnCellular(bytes: big, onCellular: true, allowCellular: true))
        XCTAssertFalse(
            DownloadQueue.asksOnCellular(bytes: DownloadQueue.cellularAskBytes, onCellular: true, allowCellular: false))
        XCTAssertFalse(DownloadQueue.asksOnCellular(bytes: nil, onCellular: true, allowCellular: false))
    }

    func testBigDownloadOnCellularWaitsThenStartsOnWiFiOrWhenAsked() throws {
        let queue = DownloadQueue(journal: root.appendingPathComponent("journal"), watchNetwork: false)
        queue.networkChanged(online: true, cellular: true)
        let url = URL(string: "http://127.0.0.1:9/never")!
        let size = DownloadQueue.cellularAskBytes + 1
        let a = try queue.enqueue(
            url: url, destination: root.appendingPathComponent("a.zip"), title: "A", totalBytes: size)
        let b = try queue.enqueue(
            url: url, destination: root.appendingPathComponent("b.zip"), title: "B", totalBytes: size)
        XCTAssertEqual(Set(queue.snapshot().map(\.state)), [.waitingWiFi])

        queue.startNow(a)
        let started = queue.snapshot().first { $0.id == a }
        XCTAssertNotEqual(started?.state, .waitingWiFi)
        XCTAssertEqual(started?.allowCellular, true)
        XCTAssertEqual(queue.snapshot().first { $0.id == b }?.state, .waitingWiFi)

        queue.networkChanged(online: true, cellular: false)
        XCTAssertNotEqual(queue.snapshot().first { $0.id == b }?.state, .waitingWiFi)
        [a, b].forEach(queue.cancel)
        XCTAssertEqual(Set(queue.snapshot().map(\.state)), [.cancelled])
    }

    func testFullDiskRefusesBeforeDownloading() {
        let queue = DownloadQueue(watchNetwork: false)
        XCTAssertThrowsError(
            try queue.enqueue(
                url: URL(string: "http://127.0.0.1:9/x")!, destination: root.appendingPathComponent("x"),
                title: "X", totalBytes: Int64.max / 2)
        ) { error in
            guard case DownloadQueue.QueueError.noDiskSpace = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(queue.snapshot().isEmpty)
    }

    func testJournalRestoresInterruptedDownloadsAsRetryOrResume() throws {
        let journal = root.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        func item(_ state: DownloadQueue.State) -> DownloadQueue.Item {
            .init(
                id: UUID(), title: state.rawValue, url: URL(string: "https://example.com/\(state)")!,
                destination: root.appendingPathComponent(state.rawValue), totalBytes: 10, completedBytes: 5,
                state: state, error: nil, sha1: "abc")
        }
        let running = item(.running)
        let resumable = item(.paused)
        let waiting = item(.waitingWiFi)
        let done = item(.finished)
        let failed = item(.failed)
        try JSONEncoder().encode([running, resumable, waiting, done, failed]).write(
            to: journal.appendingPathComponent("queue.json"))
        try Data("resume".utf8).write(to: journal.appendingPathComponent("\(resumable.id.uuidString).resume"))

        let queue = DownloadQueue(journal: journal, watchNetwork: false)
        let restored = Dictionary(uniqueKeysWithValues: queue.snapshot().map { ($0.id, $0) })
        XCTAssertNil(restored[done.id])
        XCTAssertEqual(restored[running.id]?.state, .failed)
        XCTAssertEqual(restored[running.id]?.error, DownloadQueue.interrupted)
        XCTAssertEqual(restored[running.id]?.sha1, "abc")
        XCTAssertEqual(restored[resumable.id]?.state, .paused)
        XCTAssertEqual(restored[waiting.id]?.state, .waitingWiFi)
        XCTAssertEqual(restored[failed.id]?.state, .failed)

        // Not a property list: starts over rather than crashing the session, and the stale file goes.
        queue.resume(resumable.id)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: journal.appendingPathComponent("\(resumable.id.uuidString).resume").path))
        queue.cancel(resumable.id)
        let saved = try JSONDecoder().decode(
            [DownloadQueue.Item].self, from: Data(contentsOf: journal.appendingPathComponent("queue.json")))
        XCTAssertEqual(saved.first { $0.id == resumable.id }?.state, .cancelled)
    }

    func testSummaryCountsWhatShowsOnPlay() {
        func item(_ title: String, _ state: DownloadQueue.State, done: Int64 = 0, total: Int64? = 100)
            -> DownloadQueue.Item
        {
            .init(
                id: UUID(), title: title, url: URL(string: "https://example.com")!, destination: root,
                totalBytes: total, completedBytes: done, state: state, error: nil)
        }
        var s = DownloadSummary([
            item("b", .running, done: 50), item("a", .queued, total: 300), item("c", .finished), item("d", .cancelled),
        ])
        XCTAssertEqual(s.visible.map(\.title), ["a", "b"])
        XCTAssertEqual(s.fraction, 0.125)
        XCTAssertEqual(s.title, "Downloading 2 · 12%")
        s = DownloadSummary([item("a", .failed), item("b", .paused), item("c", .waitingWiFi)])
        XCTAssertEqual(s.title, "2 downloads stopped")
        s = DownloadSummary([item("c", .waitingWiFi)])
        XCTAssertEqual(s.title, "A download waits for Wi‑Fi")
        XCTAssertTrue(DownloadSummary([item("c", .finished)]).visible.isEmpty)
    }
}
