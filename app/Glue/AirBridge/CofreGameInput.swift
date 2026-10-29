import CofreUI
import GameController
import UIKit

/// Cofre's small input facade. Air remains responsible for translating the
/// injected events into the active GLFW or SDL3 Minecraft version.
public final class CofreGameInput: NSObject, GameInputService {
    public static let shared = CofreGameInput()

    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var detectedMode: CofreInputMode = .touch
    private var policy = CofreKeyboardPolicy()
    /// Air's bridge is injected when the backend is created; it owns callback routing.
    public weak var bridge: (any CofreAirBridging)?

    public var inputMode: CofreInputMode { effectiveMode }
    public var inputModeOverride: CofreInputMode {
        get { CofreInputMode(rawValue: defaults.string(forKey: "cofre.input.mode") ?? "auto") ?? .auto }
        set {
            defaults.set(newValue.rawValue, forKey: "cofre.input.mode")
            recomputeMode()
        }
    }

    private var effectiveMode: CofreInputMode {
        inputModeOverride == .auto ? detectedMode : inputModeOverride
    }

    private override init() {
        super.init()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .GCControllerDidConnect, .GCControllerDidDisconnect,
            .GCMouseDidConnect, .GCMouseDidDisconnect,
            .GCKeyboardDidConnect, .GCKeyboardDidDisconnect,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.recomputeMode() }
        }
        observers.append(center.addObserver(
            forName: Notification.Name("CofreSDLTextInputStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let active = note.userInfo?["active"] as? Bool ?? false
            self.policy.apply(active ? .textInputRequested : .textInputStopped)
            self.continuations.values.forEach { $0.yield(active) }
        })
        recomputeMode()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func recomputeMode() {
        detectedMode = .automatic(
            hasController: !GCController.controllers().isEmpty,
            hasKeyboardOrMouse: GCKeyboard.coalesced != nil || !GCMouse.mice().isEmpty)
        NSLog("[Cofre] input mode=%@", effectiveMode.rawValue)
    }

    public func press(_ key: CofreInputKey) { keyCall(key, down: true) }
    public func release(_ key: CofreInputKey) { keyCall(key, down: false) }

    private func keyCall(_ key: CofreInputKey, down: Bool) {
        bridge?.gameInputKey(key.rawValue, down: down)
    }

    public func mouseButton(_ button: CofreMouseButton, down: Bool) {
        bridge?.gameInputMouseButton(Int(button.rawValue), down: down)
    }

    public func look(deltaX: Float, deltaY: Float) { bridge?.gameInputLookX(deltaX, y: deltaY) }

    public func textInputRequests() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(policy.shouldShow)
            continuation.onTermination = { [weak self] _ in self?.continuations.removeValue(forKey: id) }
        }
    }

    public func showKeyboard() {
        policy.apply(.manualShow)
        bridge?.setGameKeyboardShown(true)
    }

    public func hideKeyboard() {
        policy.apply(.manualHide)
        bridge?.setGameKeyboardShown(false)
    }
}

extension CofreBackendAdapter {
    public var inputMode: CofreInputMode { CofreGameInput.shared.inputMode }
    public var inputModeOverride: CofreInputMode {
        get { CofreGameInput.shared.inputModeOverride }
        set { CofreGameInput.shared.inputModeOverride = newValue }
    }
    public func press(_ key: CofreInputKey) { CofreGameInput.shared.press(key) }
    public func release(_ key: CofreInputKey) { CofreGameInput.shared.release(key) }
    public func mouseButton(_ button: CofreMouseButton, down: Bool) { CofreGameInput.shared.mouseButton(button, down: down) }
    public func look(deltaX: Float, deltaY: Float) { CofreGameInput.shared.look(deltaX: deltaX, deltaY: deltaY) }
    public func textInputRequests() -> AsyncStream<Bool> { CofreGameInput.shared.textInputRequests() }
    public func showKeyboard() { CofreGameInput.shared.showKeyboard() }
    public func hideKeyboard() { CofreGameInput.shared.hideKeyboard() }
}
