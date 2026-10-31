import XCTest
@testable import Llave

final class EventParsingTests: XCTestCase {
    func testParseStandardEvents() {
        XCTAssertEqual(LlaveEvent.parse(line: "{\"event\":\"waiting_for_unlock\"}"), .waitingForUnlock)
        XCTAssertEqual(LlaveEvent.parse(line: "{\"event\":\"waiting_for_trust\"}"), .waitingForTrust)
        XCTAssertEqual(LlaveEvent.parse(line: "{\"event\":\"paired\"}"), .paired)
        XCTAssertEqual(LlaveEvent.parse(line: "{\"event\":\"wifi_enabled\"}"), .wifiEnabled)
        XCTAssertEqual(LlaveEvent.parse(line: "{\"event\":\"validated\"}"), .validated)
        XCTAssertEqual(LlaveEvent.parse(line: "{\"event\":\"placed\"}"), .placed)
    }

    func testParseErrorEvent() {
        let line = "{\"event\":\"error\",\"code\":\"USER_DENIED\",\"message\":\"User denied prompt\"}"
        XCTAssertEqual(LlaveEvent.parse(line: line), .error(code: "USER_DENIED", message: "User denied prompt"))
    }

    func testRemotePairingFailureRemainsTypedAndActionable() {
        let event = LlaveEvent.parse(line: "{\"event\":\"error\",\"code\":\"REMOTE_PAIRING_FAILED\",\"message\":\"Pair again\"}")
        XCTAssertEqual(event, .error(code: "REMOTE_PAIRING_FAILED", message: "Pair again"))
        XCTAssertTrue(LlaveError(code: "REMOTE_PAIRING_FAILED", message: "Pair again").friendlyCopy.contains("RemotePairing"))
    }

    func testParseInvalidLines() {
        XCTAssertNil(LlaveEvent.parse(line: ""))
        XCTAssertNil(LlaveEvent.parse(line: "   \n"))
        XCTAssertNil(LlaveEvent.parse(line: "plain text message"))
        XCTAssertNil(LlaveEvent.parse(line: "{\"event\":\"unknown_event\"}"))
    }
}
