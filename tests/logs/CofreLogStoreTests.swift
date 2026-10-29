import CofreUI
import XCTest

@testable import CofreCore

final class CofreLogStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func append(_ text: String, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    func testTailReadsWholeLinesAndHoldsPartialOnes() throws {
        let url = dir.appendingPathComponent("latestlog.txt")
        var tail = LogTail()
        try append("one\n[12:00] [main/ERROR]: two\nthr", to: url)
        XCTAssertEqual(tail.read(url).map(\.text), ["one", "[12:00] [main/ERROR]: two"])
        XCTAssertEqual(tail.read(url).count, 0, "nothing new")
        try append("ee\n", to: url)
        let lines = tail.read(url)
        XCTAssertEqual(lines.map(\.text), ["three"])
        XCTAssertEqual(lines.first?.id, 2, "ids keep counting")
    }

    func testSplitUTF8CharacterWaitsForItsLine() throws {
        let url = dir.appendingPathComponent("latestlog.txt")
        let bytes = Data("café\n".utf8)
        var tail = LogTail()
        try bytes.prefix(4).write(to: url)  // "caf" plus half of "é"
        XCTAssertEqual(tail.read(url).count, 0)
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: bytes.dropFirst(4))
        try h.close()
        XCTAssertEqual(tail.read(url).map(\.text), ["café"])
    }

    func testTruncatedFileStartsOver() throws {
        let url = dir.appendingPathComponent("latestlog.txt")
        var tail = LogTail()
        try "old run line\n".write(to: url, atomically: true, encoding: .utf8)
        _ = tail.read(url)
        try "new\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(tail.read(url).map(\.text), ["new"])
    }

    func testLevels() throws {
        let url = dir.appendingPathComponent("latestlog.txt")
        var tail = LogTail()
        try append("[main/WARN]: w\n[main/ERROR]: e\njava.lang.IllegalStateException\nok\n", to: url)
        XCTAssertEqual(tail.read(url).map(\.level), [.warning, .error, .error, .info])
    }

    func testNewestCrashReportAndExport() throws {
        let reports = dir.appendingPathComponent("crash-reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let old = reports.appendingPathComponent("crash-old-client.txt")
        let new = reports.appendingPathComponent("crash-new-client.txt")
        try "old".write(to: old, atomically: true, encoding: .utf8)
        try "new".write(to: new, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: old.path)
        let previous = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(dir.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previous) }

        let store = CofreLogStore(documents: dir)
        XCTAssertEqual(store.newestCrashReport()?.lastPathComponent, new.lastPathComponent)
        XCTAssertNil(store.newestCrashReport(since: Date(timeIntervalSinceNow: 60)), "only this run's reports")
        XCTAssertThrowsError(try store.export(.latest), "no latestlog.txt yet")
        try "x\n".write(to: store.latestLog, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.export(.latest), store.latestLog)
    }

    func testGameExitReportReadsBothFiles() throws {
        let store = CofreLogStore(documents: dir)
        try "[main/ERROR]: java.lang.OutOfMemoryError: Java heap space\n".write(
            to: store.latestLog, atomically: true, encoding: .utf8)
        let report = store.gameExitReport(code: -1, instance: "Survival+")
        XCTAssertEqual(report.reason, .memory)
        XCTAssertEqual(report.files.first, store.latestLog)
        XCTAssertEqual(report.instance, "Survival+")
    }

    func testStreamFinishesWhenTheReaderStops() async throws {
        let store = CofreLogStore(documents: dir)
        try "a\nb\n".write(to: store.latestLog, atomically: true, encoding: .utf8)
        var seen: [String] = []
        for await line in store.lines(.latest) {
            seen.append(line.text)
            if seen.count == 2 { break }  // cancels the tail
        }
        XCTAssertEqual(seen, ["a", "b"])
    }
}
