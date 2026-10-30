import XCTest
@testable import CofreUI

final class GameInputTests: XCTestCase {
    func testAutomaticModePriority() {
        XCTAssertEqual(CofreInputMode.automatic(hasController: false, hasKeyboardOrMouse: false), .touch)
        XCTAssertEqual(CofreInputMode.automatic(hasController: false, hasKeyboardOrMouse: true), .keyboardMouse)
        XCTAssertEqual(CofreInputMode.automatic(hasController: true, hasKeyboardOrMouse: true), .controller)
    }
}
