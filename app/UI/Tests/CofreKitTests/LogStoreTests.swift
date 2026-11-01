import XCTest
@testable import CofreKit
final class LogStoreTests: XCTestCase {
    func testFiltersMetallumNoiseKeepsErrors() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        try "[metallum] push\nsetPipeline\nERROR kept\n".write(to: d.appendingPathComponent("latestlog.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LogStore(documents: d).read(.launcher).map(\.text), ["ERROR kept"])
    }

    func testSearchAndLevel() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        try "ok\nWARN hi\nERROR bad\n".write(to: d.appendingPathComponent("latestlog.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LogStore(documents: d).search("bad", levels: [.error]).count, 1)
    }

    func testExportRedactsSensitiveLogData() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        try "server=play.example.com path=/Users/alice/game id=00008110ABCDEF1234567890\n".write(
            to: d.appendingPathComponent("latestlog.txt"), atomically: true, encoding: .utf8)
        let exported = try LogStore(documents: d).export(.launcher)
        defer { try? FileManager.default.removeItem(at: exported) }
        let text = try String(contentsOf: exported, encoding: .utf8)
        XCTAssertFalse(text.contains("play.example.com") || text.contains("/Users/alice") || text.contains("00008110ABCDEF1234567890"))
    }

    func testRedaction() { let r = ReportBundle.redact("token=abc me@example.com player=Alex"); XCTAssertFalse(r.contains("abc") || r.contains("me@example.com") || r.contains("Alex")) }

    func testRedactionCoversDevicePathsAndHosts() {
        let raw = "id=00008110ABCDEF1234567890 path=/Users/alice/game server=play.example.com:25565 uuid=ABCDEF12-3456-7890-ABCD-EF1234567890"
        let clean = ReportBundle.redact(raw)
        XCTAssertFalse(clean.contains("00008110ABCDEF1234567890") || clean.contains("/Users/alice") || clean.contains("play.example.com") || clean.contains("ABCDEF12-3456-7890-ABCD-EF1234567890"))
    }

    func testReportJSONRedactsContext() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let raw = "server=play.example.com path=/Users/alice/game id=00008110ABCDEF1234567890"
        try raw.write(to: d.appendingPathComponent("latestlog.txt"), atomically: true, encoding: .utf8)
        let archive = d.appendingPathComponent("report.zip")
        _ = try ReportBundle(
            store: LogStore(documents: d),
            context: .init(device: "ABCDEF12-3456-7890-ABCD-EF1234567890", clue: raw)
        ).make(at: archive)
        let zip = try Data(contentsOf: archive)
        let report = try XCTUnwrap(Zip.entries(in: zip).first { $0.path == "report.json" })
        let text = String(decoding: try Zip.data(of: report, in: zip), as: UTF8.self)
        XCTAssertFalse(text.contains("play.example.com") || text.contains("/Users/alice") || text.contains("00008110ABCDEF1234567890"))
    }
}
