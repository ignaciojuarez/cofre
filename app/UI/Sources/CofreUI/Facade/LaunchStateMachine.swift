import Foundation

    /// Single launch ownership policy. UIKit/Air callbacks only advance this value; finish is idempotent.
    public struct LaunchStateMachine: Equatable, Sendable {
        public enum State: Equatable, Sendable { case preparing, surfaceShown, firstFrame, inGame, failed, cancelled, exited }
        public private(set) var state: State = .preparing
        public private(set) var awaitingFirstFrame = false
        public init() {}
        @discardableResult public mutating func event(_ event: Event) -> Bool {
            guard !isFinished else { return false }
            switch event {
            case .surfaceShown: state = .surfaceShown; awaitingFirstFrame = true
            case .firstFrame where awaitingFirstFrame: state = .inGame; awaitingFirstFrame = false
            case .failed: state = .failed; awaitingFirstFrame = false
            case .cancelled: state = .cancelled; awaitingFirstFrame = false
            case .exited: state = .exited; awaitingFirstFrame = false
            case .preparing: state = .preparing
            default: return false
            }
            return true
        }
        public var isFinished: Bool { switch state { case .inGame, .failed, .cancelled, .exited: true; default: false } }
        public enum Event: Sendable { case preparing, surfaceShown, firstFrame, failed, cancelled, exited }
    }

