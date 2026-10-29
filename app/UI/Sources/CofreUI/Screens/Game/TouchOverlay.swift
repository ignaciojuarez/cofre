import SwiftUI

// The in-game touch overlay (plan/touch-controls.md). In the world it owns every touch except the game's hotbar:
// stick, buttons, and the rest of the screen for look (drag), use (tap) and attack (hold). On a game screen it
// only shows keyboard and close, and the game handles the touches. Hardware input modes hide it.

@MainActor @Observable
public final class TouchOverlayModel {
    public var settings: TouchControlSettings
    public var screen = GameScreenState.world
    public var mode = CofreInputMode.touch
    /// Glyph context; stays `.walking` until a player-state source exists.
    public var context = PlayerContext.walking
    /// Safe area of the game window (the host updates it).
    public var insets = EdgeInsetsValue()
    public internal(set) var idle = false
    var pressed: Set<TouchControl> = []
    var sneak = SneakToggle()
    var sneakPressedAt: TimeInterval = 0
    var trayOpen = false
    var hudHidden = false
    var tabHeld = false
    /// Where the stick is centered while a thumb is on it.
    var stickCenter: CGPoint?
    var knob = CGSize.zero
    var stickKeys: Set<CofreInputKey> = []
    var world: WorldTouch?
    var hapticTick = 0
    /// Minimal: this jump press already turned into a sneak swipe.
    var swiped = false
    var pixelsPerPoint: CGFloat = 3

    let input: (any GameInputService)?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var trayOpenedByHold = false
    @ObservationIgnored private var settingsObserver: NSObjectProtocol?

    public init(input: (any GameInputService)?, settings: TouchControlSettings = .load()) {
        self.input = input
        self.settings = settings
    }

    public func start() {
        guard let input, tasks.isEmpty else { return }
        tasks.append(Task { [weak self] in
            for await mode in input.inputModeUpdates() { self?.setMode(mode) }
        })
        tasks.append(Task { [weak self] in
            for await screen in input.screenUpdates() { self?.setScreen(screen) }
        })
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let fresh = TouchControlSettings.load()
                if fresh != self.settings { self.settings = fresh }
            }
        }
        scheduleIdle()
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        idleTask?.cancel()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        releaseAll()
    }

    func setMode(_ mode: CofreInputMode) {
        if mode != .touch { releaseAll() }
        self.mode = mode
    }

    func setScreen(_ screen: GameScreenState) {
        if !screen.inWorld { releaseAll() }
        self.screen = screen
    }

    // MARK: Derived

    public var controls: [TouchControl] {
        TouchLayout.controls(style: settings.style, screen: screen, mode: mode, hudHidden: hudHidden)
    }

    var holding: Bool { !pressed.isEmpty || stickCenter != nil || world != nil }

    public var opacity: Double {
        if hudHidden { return 0.3 }
        return settings.opacity(idleFor: idle ? .infinity : 0, holding: holding)
    }

    func frames(in size: CGSize) -> [TouchControl: CGRect] {
        TouchLayout.frames(
            style: settings.style, size: size, insets: insets,
            scale: TouchLayout.scale(for: size, buttonScale: settings.buttonScale), leftHanded: settings.leftHanded,
            hotbar: hotbar(in: size))
    }

    func hotbar(in size: CGSize) -> CGRect {
        TouchLayout.hotbar(in: size, screen: screen, defaultPixelsPerPoint: pixelsPerPoint)
    }

    /// Hit test for the UIKit host: which touches the overlay keeps (the rest go to the game).
    public func captures(_ p: CGPoint, in size: CGSize) -> Bool {
        let shown = controls
        guard !shown.isEmpty else { return false }
        let f = frames(in: size)
        if trayOpen { return true }
        if screen.inWorld {
            let docked = shown.filter { $0 == .chat || $0 == .inventory }.compactMap { f[$0] }
            if docked.contains(where: { TouchLayout.hitRect($0).contains(p) }) { return true }
            return !hotbar(in: size).contains(p)
        }
        return shown.compactMap { f[$0] }.contains { TouchLayout.hitRect($0).contains(p) }
    }

    // MARK: Idle (rule U4)

    func touched() {
        if idle { idle = false }
        input?.noteTouchInput()
        scheduleIdle()
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TouchControlSettings.idleDelay))
            guard !Task.isCancelled, let self, !self.holding else { return }
            self.idle = true
        }
    }

    // MARK: Keys

    private var down: Set<CofreInputKey> = []

    func press(_ key: CofreInputKey) {
        guard down.insert(key).inserted else { return }
        input?.press(key)
    }

    func release(_ key: CofreInputKey) {
        guard down.remove(key) != nil else { return }
        input?.release(key)
    }

    func tap(_ key: CofreInputKey) {
        press(key)
        release(key)
    }

    private func buzz() { if settings.haptics { hapticTick += 1 } }

    func releaseAll() {
        down.forEach { input?.release($0) }
        down = []
        if world?.attacking == true { input?.mouseButton(.left, down: false) }
        world = nil
        stickCenter = nil
        knob = .zero
        stickKeys = []
        pressed = []
        sneak = SneakToggle()
        tabHeld = false
        trayOpen = false
        holdTask?.cancel()
    }

    // MARK: Buttons

    func buttonDown(_ c: TouchControl) {
        guard pressed.insert(c).inserted else { return }
        touched()
        buzz()
        let now = ProcessInfo.processInfo.systemUptime
        switch c {
        case .jump: press(.jump)
        case .sneak:
            sneakPressedAt = now
            if sneak.press(time: now) { press(.sneak) }
        case .pause:
            trayOpenedByHold = false
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self else { return }
                self.trayOpenedByHold = true
                self.trayOpen = true
                self.buzz()
            }
        default: break
        }
    }

    func buttonUp(_ c: TouchControl) {
        guard pressed.remove(c) != nil else { return }
        scheduleIdle()
        let now = ProcessInfo.processInfo.systemUptime
        switch c {
        case .jump: release(.jump)
        case .sneak:
            if sneak.release(time: now, pressedAt: sneakPressedAt) { release(.sneak) }
        case .pause:
            holdTask?.cancel()
            if trayOpenedByHold { return }
            if trayOpen { trayOpen = false } else { tap(.escape) }
        case .menu: trayOpen.toggle()
        case .chat: tap(.chat)
        case .inventory: tap(.inventory)
        case .keyboard: input?.showKeyboard()
        case .close: tap(.escape)
        case .stick: break
        }
    }

    /// Minimal layout: swipe down on jump toggles sneak.
    func jumpSwipedDown() {
        if sneak.toggle() { press(.sneak) } else { release(.sneak) }
        buzz()
    }

    func select(_ item: TrayItem) {
        touched()
        buzz()
        if item != .players { trayOpen = false }
        switch item {
        case .pause: tap(.escape)
        case .chat: tap(.chat)
        case .inventory: tap(.inventory)
        case .view: tap(.f5)
        case .players:
            tabHeld.toggle()
            tabHeld ? press(.tab) : release(.tab)
        case .drop: tap(.drop)
        case .swap: tap(.swapHands)
        case .hideHUD:
            tap(.f1)
            hudHidden.toggle()
        case .keyboard: input?.showKeyboard()
        }
    }

    // MARK: Stick

    func stickBegan(at p: CGPoint, rest: CGRect) {
        touched()
        stickCenter = settings.style == .classic ? CGPoint(x: rest.midX, y: rest.midY) : p
        stickMoved(to: p, radius: rest.width / 2)
    }

    func stickMoved(to p: CGPoint, radius: CGFloat) {
        guard let c = stickCenter else { return }
        var d = CGSize(width: p.x - c.x, height: p.y - c.y)
        let len = hypot(d.width, d.height), limit = radius * 0.59
        if len > limit { d = CGSize(width: d.width / len * limit, height: d.height / len * limit) }
        knob = d
        let keys = StickKeys.keys(dx: d.width, dy: d.height, radius: limit)
        for k in stickKeys.subtracting(keys) { release(k) }
        for k in keys.subtracting(stickKeys) { press(k) }
        stickKeys = keys
    }

    func stickEnded() {
        stickKeys.forEach(release)
        stickKeys = []
        stickCenter = nil
        knob = .zero
        scheduleIdle()
    }

    // MARK: World (look, use, attack)

    func worldBegan(at p: CGPoint) {
        touched()
        if trayOpen {
            trayOpen = false
            return
        }
        if tabHeld {
            tabHeld = false
            release(.tab)
        }
        world = WorldTouch(at: p, time: ProcessInfo.processInfo.systemUptime)
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WorldTouch.holdAfter))
            guard !Task.isCancelled, let self, var w = self.world else { return }
            let actions = w.tick(time: ProcessInfo.processInfo.systemUptime)
            self.world = w
            self.perform(actions)
        }
    }

    func worldMoved(to p: CGPoint) {
        guard var w = world else { return }
        let actions = w.move(to: p, time: ProcessInfo.processInfo.systemUptime)
        world = w
        perform(actions)
    }

    func worldEnded() {
        holdTask?.cancel()
        guard var w = world else { return }
        let actions = w.end(time: ProcessInfo.processInfo.systemUptime)
        world = nil
        perform(actions)
        scheduleIdle()
    }

    private func perform(_ actions: [WorldTouch.Action]) {
        for a in actions {
            switch a {
            case .look(let dx, let dy):
                let d = settings.lookDelta(dx: dx, dy: dy, pixelsPerPoint: pixelsPerPoint)
                input?.look(deltaX: d.x, deltaY: d.y)
            case .use:
                input?.mouseButton(.right, down: true)
                input?.mouseButton(.right, down: false)
            case .attackDown:
                buzz()
                input?.mouseButton(.left, down: true)
            case .attackUp: input?.mouseButton(.left, down: false)
            }
        }
    }
}

// MARK: - View

public struct TouchOverlayView: View {
    @Bindable var model: TouchOverlayModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: TouchOverlayModel) { self.model = model }

    public var body: some View {
        GeometryReader { g in
            let size = g.size
            let f = model.frames(in: size)
            let k = TouchLayout.scale(for: size, buttonScale: model.settings.buttonScale)
            let shown = model.controls
            ZStack(alignment: .topLeading) {
                if model.screen.inWorld && !shown.isEmpty { lookSurface }
                if shown.contains(.stick), let rest = f[.stick] { stick(rest: rest, size: size) }
                ForEach(shown.filter { $0 != .stick }, id: \.self) { c in
                    if let r = f[c] { button(c, frame: r) }
                }
                if model.trayOpen, let anchor = f[model.settings.style == .minimal ? .menu : .pause] {
                    tray(anchor: anchor, size: size, k: k)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .opacity(model.opacity)
            .animation(
                reduceMotion ? nil : .easeOut(duration: model.idle ? 0.4 : TouchControlSettings.restoreDuration),
                value: model.opacity)
        }
        .ignoresSafeArea()
        .onAppear { model.pixelsPerPoint = displayScale }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: model.hapticTick)
    }

    private var lookSurface: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if model.world == nil && v.translation == .zero { model.worldBegan(at: v.startLocation) }
                        model.worldMoved(to: v.location)
                    }
                    .onEnded { _ in model.worldEnded() }
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder private func stick(rest: CGRect, size: CGSize) -> some View {
        let style = model.settings.style
        let zone = style == .classic ? TouchLayout.hitRect(rest) : TouchLayout.stickZone(size: size, leftHanded: model.settings.leftHanded)
        Color.clear.frame(width: zone.width, height: zone.height).contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if model.stickCenter == nil {
                            model.stickBegan(at: CGPoint(x: zone.minX + v.startLocation.x, y: zone.minY + v.startLocation.y), rest: rest)
                        }
                        model.stickMoved(
                            to: CGPoint(x: zone.minX + v.location.x, y: zone.minY + v.location.y), radius: rest.width / 2)
                    }
                    .onEnded { _ in model.stickEnded() }
            )
            .accessibilityLabel(Text("Move"))
            .position(x: zone.midX, y: zone.midY)
        let center = model.stickCenter ?? CGPoint(x: rest.midX, y: rest.midY)
        if style != .minimal || model.stickCenter != nil {
            StickView(
                size: rest.width, knob: model.knob, sprinting: model.stickKeys.contains(.sprint),
                faint: model.idle && model.stickCenter == nil
            )
            .position(center)
            .allowsHitTesting(false)
        }
    }

    private func glyph(_ c: TouchControl) -> OverlayGlyph {
        switch c {
        case .jump: OverlayGlyph(TouchLayout.jumpGlyph(model.context))
        case .sneak: OverlayGlyph(TouchLayout.sneakGlyph(model.context))
        case .pause: .pause
        case .chat: .chat
        case .inventory: .dots
        case .menu: .menu
        case .keyboard: .keyboard
        case .close: .close
        case .stick: .jump
        }
    }

    private func label(_ c: TouchControl) -> Text {
        switch c {
        case .jump: Text("Jump")
        case .sneak: model.sneak.locked ? Text("Sneak, locked") : Text("Sneak")
        case .pause: Text("Pause")
        case .chat: Text("Chat")
        case .inventory: Text("Inventory")
        case .menu: Text("More")
        case .keyboard: Text("Keyboard")
        case .close: Text("Close")
        case .stick: Text("Move")
        }
    }

    private func button(_ c: TouchControl, frame r: CGRect) -> some View {
        let hit = TouchLayout.hitRect(r)
        let on = (c == .sneak && model.sneak.locked) || (model.trayOpen && (c == .pause || c == .menu))
            || (model.tabHeld && c == .pause)
        let docked = model.screen.inWorld && (c == .chat || c == .inventory) && model.settings.style != .classic
        return OverlayButton(
            glyph: glyph(c), size: r.width, on: on, pressed: model.pressed.contains(c),
            flat: docked || (c == .inventory),
            label: c == .sneak && model.context == .riding ? String(localized: "Dismount") : nil
        )
        .frame(width: hit.width, height: hit.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    model.buttonDown(c)
                    if c == .jump, model.settings.style == .minimal, v.translation.height > 24, !model.swiped {
                        model.swiped = true
                        model.jumpSwipedDown()
                    }
                }
                .onEnded { _ in
                    model.swiped = false
                    model.buttonUp(c)
                }
        )
        .accessibilityElement()
        .accessibilityLabel(label(c))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            model.buttonDown(c)
            model.buttonUp(c)
        }
        .position(x: hit.midX, y: hit.midY)
    }

    private func tray(anchor: CGRect, size: CGSize, k: CGFloat) -> some View {
        let left = model.settings.leftHanded
        return QuickTray(
            items: TrayItem.items(for: model.settings.style), k: k, on: model.tabHeld ? [.players] : [],
            select: model.select
        )
        .fixedSize()
        .padding(.top, anchor.maxY + 8)
        .padding(left ? .leading : .trailing, left ? anchor.minX : size.width - anchor.maxX)
        .frame(width: size.width, height: size.height, alignment: left ? .topLeading : .topTrailing)
    }
}

#if canImport(UIKit)
    import UIKit

    /// Hosts the overlay over the game view. Touches the overlay doesn't keep fall through to the game.
    public final class TouchOverlayController: UIViewController {
        public let model: TouchOverlayModel

        public init(input: any GameInputService) {
            model = TouchOverlayModel(input: input)
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError() }

        public override func loadView() { view = PassthroughView(model: model) }

        public override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isMultipleTouchEnabled = true
            let host = UIHostingController(rootView: TouchOverlayView(model: model))
            host.view.backgroundColor = .clear
            host.view.isMultipleTouchEnabled = true
            host.safeAreaRegions = []
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
            model.pixelsPerPoint = view.window?.screen.scale ?? 3
            model.start()
            NSLog("[Cofre] touch overlay ready style=%@", model.settings.style.rawValue)
        }

        public override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            let i = view.safeAreaInsets
            model.insets = EdgeInsetsValue(top: i.top, left: i.left, bottom: i.bottom, right: i.right)
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            model.pixelsPerPoint = view.window?.screen.scale ?? model.pixelsPerPoint
        }

        deinit { MainActor.assumeIsolated { model.stop() } }
    }

    final class PassthroughView: UIView {
        let model: TouchOverlayModel
        init(model: TouchOverlayModel) {
            self.model = model
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // Every touch counts as touch input, even ones that fall through: that's how Auto leaves controller
            // or keyboard mode while the overlay is hidden.
            if event?.type == .touches { model.touched() }
            return model.captures(point, in: bounds.size) ? super.hitTest(point, with: event) : nil
        }
    }
#endif
