import XCTest
@testable import CofreUI

final class LaunchStateMachineTests: XCTestCase {
    func testFirstFrameAndDoubleFinish() {
        var machine = LaunchStateMachine()
        XCTAssertTrue(machine.event(.surfaceShown))
        XCTAssertTrue(machine.event(.firstFrame))
        XCTAssertFalse(machine.event(.failed))
        XCTAssertEqual(machine.state, .inGame)
    }

    func testCancelExitAndTimeoutFailure() {
        var cancelled = LaunchStateMachine()
        _ = cancelled.event(.cancelled)
        XCTAssertEqual(cancelled.state, .cancelled)
        var exited = LaunchStateMachine()
        _ = exited.event(.exited)
        XCTAssertEqual(exited.state, .exited)
        var timeout = LaunchStateMachine()
        _ = timeout.event(.surfaceShown)
        _ = timeout.event(.failed)
        XCTAssertEqual(timeout.state, .failed)
    }
}
