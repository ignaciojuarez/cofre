import XCTest
@testable import CofreKit

final class GameSessionTests: XCTestCase {
    func testConsumeReturnsAndClearsSession() {
        let suite = "GameSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let startedAt = Date(timeIntervalSince1970: 1234)

        GameSessionMarker.begin(instanceID: "neoforge", at: startedAt, defaults: defaults)

        let session = GameSessionMarker.consume(defaults: defaults)
        XCTAssertEqual(session?.instanceID, "neoforge")
        XCTAssertEqual(session?.startedAt, startedAt)
        XCTAssertNil(GameSessionMarker.consume(defaults: defaults))
    }

    func testClearDropsAnActiveSession() {
        let suite = "GameSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        GameSessionMarker.begin(instanceID: "survival", defaults: defaults)
        GameSessionMarker.clear(defaults: defaults)

        XCTAssertNil(GameSessionMarker.consume(defaults: defaults))
    }
}
