import XCTest
@testable import CofreKit

final class AccountsTests: XCTestCase {
    func testListStatesAndRemoveSelectsAnother() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("accounts"), withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func write(_ id: String, _ value: [String: Any]) throws { try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("accounts/\(id).json")) }
        try write("ready", ["accountId":"ready", "username":"Ready", "xuid":"1", "expiresAt":1_800_000_000])
        try write("old", ["accountId":"old", "username":"Old", "xuid":"2", "expiresAt":1_600_000_000])
        try write("demo", ["accountId":"demo", "username":"Demo", "demo":true])
        var selected: String? = "old"
        let store = AccountStore(directory: root, now: { now }, readSelected: { selected }, writeSelected: { selected = $0 })
        XCTAssertEqual(store.list().first { $0.id == "ready" }?.state, .ready)
        // A past access-token date is renewed at launch, so the account is still ready.
        XCTAssertEqual(store.list().first { $0.id == "old" }?.state, .ready)
        XCTAssertEqual(store.list().first { $0.id == "demo" }?.state, .demo)
        try store.remove(id: "old")
        XCTAssertEqual(selected, "demo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("accounts/old.json").path))
    }
}
