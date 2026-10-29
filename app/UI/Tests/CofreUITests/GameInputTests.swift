import XCTest
@testable import CofreUI

final class GameInputTests: XCTestCase {
    func testAutomaticModePriority() {
        XCTAssertEqual(CofreInputMode.automatic(hasController: false, hasKeyboardOrMouse: false), .touch)
        XCTAssertEqual(CofreInputMode.automatic(hasController: false, hasKeyboardOrMouse: true), .keyboardMouse)
        XCTAssertEqual(CofreInputMode.automatic(hasController: true, hasKeyboardOrMouse: true), .controller)
    }

    func testKeyboardPolicyFollowsFocusAndManualOverride() {
        var policy = CofreKeyboardPolicy()
        XCTAssertFalse(policy.shouldShow)
        policy.apply(.textInputRequested)
        XCTAssertTrue(policy.shouldShow)
        policy.apply(.textInputStopped)
        XCTAssertFalse(policy.shouldShow)
        policy.apply(.manualShow)
        policy.apply(.textInputStopped)
        XCTAssertTrue(policy.shouldShow)
        policy.apply(.manualHide)
        XCTAssertFalse(policy.shouldShow)
    }
}
