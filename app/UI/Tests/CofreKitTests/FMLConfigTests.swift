import XCTest
@testable import CofreKit

final class FMLConfigTests: XCTestCase {
    func testEarlyWindowIsTurnedOffOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config/fml.toml")

        // No file yet (first launch): created with just the setting; FML adds its defaults.
        try FMLConfig.disableEarlyWindow(in: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "earlyWindowControl = false")

        // FML's own file: only that line changes.
        let original = "#Should we control the window.\nearlyWindowControl = true\nmaxThreads = -1\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        try FMLConfig.disableEarlyWindow(in: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original.replacingOccurrences(of: "= true", with: "= false"))
        try FMLConfig.disableEarlyWindow(in: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).components(separatedBy: "earlyWindowControl").count, 2)
    }
}
