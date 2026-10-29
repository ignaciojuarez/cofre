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
    private var modeContinuations: [UUID: AsyncStream<CofreInputMode>.Continuation] = [:]
    private var detectedMode: CofreInputMode = .touch
    /// Auto: the last input used wins (plan/touch-controls.md U10).
    private var tracker = CofreInputModeTracker()
    private var lastAnnounced: CofreInputMode?
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
        // "Became current" fires when a pad or mouse is actually used; the handlers below catch every press.
        observers.append(center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) {
            [weak self] note in
            if let pad = note.object as? GCController { self?.watch(pad) }
            self?.used(.controller)
        })
        observers.append(center.addObserver(forName: .GCMouseDidBecomeCurrent, object: nil, queue: .main) {
            [weak self] _ in self?.used(.keyboardMouse)
        })
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
        tracker.hasController = !GCController.controllers().isEmpty
        tracker.hasKeyboardOrMouse = GCKeyboard.coalesced != nil || !GCMouse.mice().isEmpty
        GCController.controllers().forEach(watch)
        watchKeyboard()
        announce()
    }

    private func used(_ mode: CofreInputMode) {
        guard tracker.lastUsed != mode else { return }
        tracker.used(mode)
        announce()
    }

    private func announce() {
        detectedMode = tracker.mode
        let mode = effectiveMode
        guard mode != lastAnnounced else { return }
        lastAnnounced = mode
        NSLog("[Cofre] input mode=%@", mode.rawValue)
        modeContinuations.values.forEach { $0.yield(mode) }
    }

    /// Chains onto the pad's handler (Air's stays first) so any press counts as controller use.
    private var watchedPads = NSHashTable<GCController>.weakObjects()
    private func watch(_ pad: GCController) {
        guard !watchedPads.contains(pad), let gamepad = pad.extendedGamepad else { return }
        watchedPads.add(pad)
        let previous = gamepad.valueChangedHandler
        gamepad.valueChangedHandler = { [weak self] g, e in
            previous?(g, e)
            DispatchQueue.main.async { self?.used(.controller) }
        }
    }

    private var keyboardWatched = false
    private func watchKeyboard() {
        guard !keyboardWatched, let input = GCKeyboard.coalesced?.keyboardInput else { return }
        keyboardWatched = true
        let previous = input.keyChangedHandler
        input.keyChangedHandler = { [weak self] k, b, code, pressed in
            previous?(k, b, code, pressed)
            DispatchQueue.main.async { self?.used(.keyboardMouse) }
        }
    }

    public func inputModeUpdates() -> AsyncStream<CofreInputMode> {
        AsyncStream { continuation in
            let id = UUID()
            modeContinuations[id] = continuation
            continuation.yield(effectiveMode)
            continuation.onTermination = { [weak self] _ in
                DispatchQueue.main.async { self?.modeContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func noteTouchInput() { used(.touch) }

    /// Polls Air ten times a second while someone listens; yields on change.
    public func screenUpdates() -> AsyncStream<GameScreenState> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                var last: GameScreenState?
                while !Task.isCancelled {
                    let now = self?.screenState() ?? .world
                    if now != last {
                        last = now
                        continuation.yield(now)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func screenState() -> GameScreenState {
        guard let d = bridge?.gameScreenState() else { return .world }
        let gui = d["guiScale"]?.intValue ?? 0, ppp = d["pixelsPerPoint"]?.doubleValue ?? 0
        return GameScreenState(
            inWorld: d["inWorld"]?.boolValue ?? true, guiScale: gui > 0 ? gui : nil,
            pixelsPerPoint: ppp > 0 ? ppp : nil)
    }

    public func scroll(steps: Int) { bridge?.gameInputScroll(steps) }

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
    public func inputModeUpdates() -> AsyncStream<CofreInputMode> { CofreGameInput.shared.inputModeUpdates() }
    public func screenUpdates() -> AsyncStream<GameScreenState> { CofreGameInput.shared.screenUpdates() }
    public func noteTouchInput() { CofreGameInput.shared.noteTouchInput() }
    public func scroll(steps: Int) { CofreGameInput.shared.scroll(steps: steps) }
}
