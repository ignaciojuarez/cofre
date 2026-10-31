import CoreGraphics
import Foundation
import CofreKit

// In-game touch controls: settings, layout and gesture rules (plan/touch-controls.md). Pure values, so the
// overlay view stays thin and tests cover the rules.

public enum TouchLayoutStyle: String, CaseIterable, Codable, Sendable {
    /// C: Bedrock positions, chat and inventory docked on the hotbar, extras behind a held pause.
    case dock
    /// A: Bedrock's layout, chat and pause top-right.
    case classic
    /// B: jump and ≡ only; the stick appears under the thumb.
    case minimal

    public var title: String {
        switch self {
        case .dock: String(localized: "Dock")
        case .classic: String(localized: "Classic")
        case .minimal: String(localized: "Minimal")
        }
    }
}

public struct TouchControlSettings: Codable, Equatable, Sendable {
    public var style = TouchLayoutStyle.dock
    /// 0.6–1.5, on top of the window scale.
    public var buttonScale = 1.0
    /// 0.2–1.
    public var opacity = 0.8
    public var fadeWhenIdle = true
    public var leftHanded = false
    public var haptics = true
    /// 0.25–3.
    public var lookSensitivity = 1.0
    public var invertY = false
    /// 0.2–0.6 of the screen's width, from the stick's edge: every touch that starts there moves, never looks.
    public var stickArea = 0.4
    /// Seconds a finger rests on the world before it breaks (0.1–0.5). Shorter touches place or use.
    public var holdToBreak = WorldTouch.defaultHold
    /// Bedrock-style Attack and Use buttons replace world taps and holds.
    public var actionButtons = false

    public init() {}

    /// Missing keys keep their defaults, so a setting added later doesn't reset the saved ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        style = try c.decodeIfPresent(TouchLayoutStyle.self, forKey: .style) ?? d.style
        buttonScale = try c.decodeIfPresent(Double.self, forKey: .buttonScale) ?? d.buttonScale
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        fadeWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .fadeWhenIdle) ?? d.fadeWhenIdle
        leftHanded = try c.decodeIfPresent(Bool.self, forKey: .leftHanded) ?? d.leftHanded
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        lookSensitivity = try c.decodeIfPresent(Double.self, forKey: .lookSensitivity) ?? d.lookSensitivity
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? d.invertY
        stickArea = try c.decodeIfPresent(Double.self, forKey: .stickArea) ?? d.stickArea
        holdToBreak = try c.decodeIfPresent(Double.self, forKey: .holdToBreak) ?? d.holdToBreak
        actionButtons = try c.decodeIfPresent(Bool.self, forKey: .actionButtons) ?? d.actionButtons
    }

    public static let idleOpacity = 0.35
    public static let idleDelay: TimeInterval = 3
    public static let restoreDuration: TimeInterval = 0.15

    static var key: String { PreferenceKey.touchSettings.rawValue }

    public static func load(_ defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// Rule U4: full opacity while touched or held, the idle level after `idleDelay` without touches.
    public func opacity(idleFor: TimeInterval, holding: Bool) -> Double {
        guard fadeWhenIdle, !holding, idleFor >= Self.idleDelay else { return opacity }
        return min(opacity, Self.idleOpacity)
    }

    /// Points dragged → look delta in pixels, with sensitivity and Invert Y.
    public func lookDelta(dx: CGFloat, dy: CGFloat, pixelsPerPoint: CGFloat) -> (x: Float, y: Float) {
        let k = pixelsPerPoint * lookSensitivity
        return (Float(dx * k), Float(dy * k * (invertY ? -1 : 1)))
    }
}

public enum TouchControl: String, CaseIterable, Sendable {
    case stick, jump, sneak, attack, use, pause, chat, inventory, menu, keyboard, close
}

/// What the player is doing, when a state source exists. Only changes glyphs (rule U3).
public enum PlayerContext: Sendable { case walking, flying, swimming, riding }

public enum TouchGlyph: Equatable, Sendable {
    case jump, sneak, flyUp, flyDown, swimUp, swimDown, dismount
}

public enum TouchLayout {
    /// Rule U1: what's on screen for this style, screen and input mode. Hardware modes hide everything.
    public static func controls(
        style: TouchLayoutStyle, screen: GameScreenState, mode: CofreInputMode, hudHidden: Bool = false,
        actionButtons: Bool = false
    ) -> [TouchControl] {
        guard mode == .touch || mode == .auto else { return [] }
        guard screen.inWorld else { return [.keyboard, .close] }
        if hudHidden { return [style == .minimal ? .menu : .pause] }
        switch style {
        case .dock, .classic:
            return actionButtons
                ? [.stick, .jump, .sneak, .attack, .use, .pause, .chat, .inventory]
                : [.stick, .jump, .sneak, .pause, .chat, .inventory]
        case .minimal:
            return actionButtons ? [.stick, .jump, .attack, .use, .menu] : [.stick, .jump, .menu]
        }
    }

    public static func jumpGlyph(_ context: PlayerContext) -> TouchGlyph {
        switch context {
        case .flying: .flyUp
        case .swimming: .swimUp
        case .walking, .riding: .jump
        }
    }

    public static func sneakGlyph(_ context: PlayerContext) -> TouchGlyph {
        switch context {
        case .flying: .flyDown
        case .swimming: .swimDown
        case .riding: .dismount
        case .walking: .sneak
        }
    }

    /// Rule U6: the window's short side over an iPhone's landscape height, clamped, times the user's size.
    public static func scale(for size: CGSize, buttonScale: Double = 1) -> CGFloat {
        min(max(min(size.width, size.height) / 402, 1), 1.35) * buttonScale
    }

    /// Minecraft's hotbar in points: 182×22 GUI pixels, bottom-centered. Without a GUI scale from the game,
    /// use Minecraft's auto rule (largest scale that keeps 320×240 GUI pixels) on the window's pixels.
    public static func hotbar(in size: CGSize, screen: GameScreenState, defaultPixelsPerPoint: CGFloat) -> CGRect {
        let ppp = CGFloat(screen.pixelsPerPoint ?? Double(defaultPixelsPerPoint))
        let gui = CGFloat(screen.guiScale ?? autoGuiScale(width: size.width * ppp, height: size.height * ppp))
        let w = 182 * gui / ppp, h = 22 * gui / ppp
        return CGRect(x: (size.width - w) / 2, y: size.height - h, width: w, height: h)
    }

    /// Which of the 9 hotbar slots (0-based) a point falls on, if any.
    public static func hotbarSlot(at p: CGPoint, in hotbar: CGRect) -> Int? {
        guard hotbar.contains(p) else { return nil }
        return min(8, Int((p.x - hotbar.minX) / (hotbar.width / 9)))
    }

    static func autoGuiScale(width: CGFloat, height: CGFloat) -> Int {
        var scale = 1
        while CGFloat(scale + 1) * 320 <= width && CGFloat(scale + 1) * 240 <= height { scale += 1 }
        return scale
    }

    /// Frames in the overlay's coordinate space. Laid out right-handed, then mirrored for left-handed play;
    /// the hotbar dock stays put because the game's hotbar doesn't mirror.
    public static func frames(
        style: TouchLayoutStyle, size: CGSize, insets: EdgeInsetsValue, scale k: CGFloat, leftHanded: Bool,
        hotbar: CGRect, actionButtons: Bool = false
    ) -> [TouchControl: CGRect] {
        let left = insets.left + 16, right = size.width - insets.right - 16
        let bottom = size.height - insets.bottom - 14, top = insets.top + 10
        var f: [TouchControl: CGRect] = [:]
        let stick = 112 * k
        f[.stick] = CGRect(x: left, y: bottom - stick, width: stick, height: stick)
        let jump = 60 * k
        f[.jump] = CGRect(x: right - jump, y: bottom - jump, width: jump, height: jump)
        switch style {
        case .dock:
            let sneak = 46 * k
            f[.sneak] = CGRect(x: right - jump - 4 * k - sneak, y: bottom - jump - 34 * k, width: sneak, height: sneak)
            f[.pause] = CGRect(x: right - 36 * k, y: top, width: 36 * k, height: 36 * k)
        case .classic:
            let sneak = 52 * k
            f[.sneak] = CGRect(x: right - jump - 12 * k - sneak, y: bottom - sneak, width: sneak, height: sneak)
            f[.pause] = CGRect(x: right - 40 * k, y: top, width: 40 * k, height: 40 * k)
            f[.chat] = CGRect(x: right - 88 * k, y: top, width: 40 * k, height: 40 * k)
        case .minimal:
            f[.menu] = CGRect(x: right - 36 * k, y: top, width: 36 * k, height: 36 * k)
        }
        if actionButtons {
            let action = 52 * k
            let gap = 8 * k
            switch style {
            case .dock:
                let sneak = f[.sneak]!
                f[.attack] = CGRect(x: sneak.minX - gap - action, y: sneak.minY, width: action, height: action)
                f[.use] = CGRect(x: sneak.minX, y: sneak.maxY + gap, width: action, height: action)
            case .classic:
                let sneak = f[.sneak]!
                let y = max(top, sneak.minY - gap - action)
                f[.attack] = CGRect(x: sneak.minX - gap - action, y: y, width: action, height: action)
                f[.use] = CGRect(x: sneak.minX, y: y, width: action, height: action)
            case .minimal:
                let jump = f[.jump]!
                let y = max(top, jump.minY - gap - action)
                f[.attack] = CGRect(x: jump.minX - gap - action, y: y, width: action, height: action)
                f[.use] = CGRect(x: jump.minX, y: y, width: action, height: action)
            }
        }
        let kb = 40 * k
        f[.close] = CGRect(x: right - kb, y: top, width: kb, height: kb)
        f[.keyboard] = CGRect(x: right - 2 * kb - 8, y: top, width: kb, height: kb)
        if leftHanded {
            for (id, r) in f { f[id] = CGRect(x: size.width - r.maxX, y: r.minY, width: r.width, height: r.height) }
        }
        // Docked on the hotbar (never mirrored).
        let side = max(hotbar.height, 30)
        let y = hotbar.maxY - side
        if style == .dock {
            f[.chat] = CGRect(x: hotbar.minX - 2 - side, y: y, width: side, height: side)
        }
        if style != .minimal {
            f[.inventory] = CGRect(x: hotbar.maxX + 2, y: y, width: side, height: side)
        }
        return f
    }

    /// The stick's strip of the screen, full height: a touch that starts there always moves (the stick appears
    /// under the thumb), so it can never turn the camera first. Buttons and the hotbar on top still win.
    public static func stickZone(size: CGSize, leftHanded: Bool, fraction: Double = 0.4) -> CGRect {
        let w = size.width * min(max(fraction, 0.2), 0.6)
        return CGRect(x: leftHanded ? size.width - w : 0, y: 0, width: w, height: size.height)
    }

    /// The look region is a sibling of the stick region, so the first drag
    /// event can never move the camera before the floating stick owns it.
    public static func lookZone(size: CGSize, leftHanded: Bool, fraction: Double = 0.4) -> CGRect {
        let stick = stickZone(size: size, leftHanded: leftHanded, fraction: fraction)
        return leftHanded
            ? CGRect(x: 0, y: 0, width: stick.minX, height: size.height)
            : CGRect(x: stick.maxX, y: 0, width: size.width - stick.maxX, height: size.height)
    }

    /// Rule U5: every target gets at least 44×44 pt.
    public static func hitRect(_ r: CGRect) -> CGRect {
        r.insetBy(dx: min(0, (r.width - 44) / 2), dy: min(0, (r.height - 44) / 2))
    }
}

/// Safe-area insets without SwiftUI/UIKit, so layout stays testable on any platform.
public struct EdgeInsetsValue: Equatable, Sendable {
    public var top, left, bottom, right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

// MARK: - Gestures

/// Stick offset → movement keys. 8-way, with a dead zone; pushing to the top edge also sprints.
public enum StickKeys {
    public static let deadZone = 0.25, sprintAt = 0.9

    public static func keys(dx: CGFloat, dy: CGFloat, radius: CGFloat) -> Set<CofreInputKey> {
        guard radius > 0 else { return [] }
        let x = dx / radius, y = dy / radius
        guard hypot(x, y) >= deadZone else { return [] }
        let angle = atan2(-y, x)  // 0 = right, π/2 = forward
        var keys: Set<CofreInputKey> = []
        let sector = Int(((angle + .pi * 2 + .pi / 8).truncatingRemainder(dividingBy: .pi * 2)) / (.pi / 4))
        switch sector {
        case 0: keys = [.d]
        case 1: keys = [.w, .d]
        case 2: keys = [.w]
        case 3: keys = [.w, .a]
        case 4: keys = [.a]
        case 5: keys = [.s, .a]
        case 6: keys = [.s]
        default: keys = [.s, .d]
        }
        if -y >= sprintAt, keys.contains(.w) { keys.insert(.sprint) }
        return keys
    }
}

/// One finger on the world: tap = use, hold = attack/break (and keeps breaking while it drags), drag = look.
public struct WorldTouch: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case look(dx: CGFloat, dy: CGFloat), use, attackDown, attackUp }

    public static let defaultHold: TimeInterval = 0.2, slop: CGFloat = 10

    let start: CGPoint, startTime: TimeInterval
    /// How long the finger rests before the hold breaks; a shorter touch is a tap (use).
    let holdAfter: TimeInterval
    /// Action buttons keep world gestures for camera look only.
    let lookOnly: Bool
    var last: CGPoint
    public private(set) var looking = false, attacking = false

    public init(
        at p: CGPoint, time: TimeInterval, holdAfter: TimeInterval = defaultHold, lookOnly: Bool = false
    ) {
        start = p
        last = p
        startTime = time
        self.holdAfter = holdAfter
        self.lookOnly = lookOnly
    }

    public mutating func move(to p: CGPoint, time: TimeInterval) -> [Action] {
        var out = tick(time: time)
        if !looking, hypot(p.x - start.x, p.y - start.y) >= Self.slop { looking = true }
        if looking {
            out.append(.look(dx: p.x - last.x, dy: p.y - last.y))
            last = p
        }
        return out
    }

    /// Call while the finger rests; starts the hold once it has stayed put long enough.
    public mutating func tick(time: TimeInterval) -> [Action] {
        guard !lookOnly, !looking, !attacking, time - startTime >= holdAfter else { return [] }
        attacking = true
        return [.attackDown]
    }

    public mutating func end(time: TimeInterval) -> [Action] {
        if lookOnly { return [] }
        if attacking { return [.attackUp] }
        if !looking, time - startTime <= holdAfter { return [.use] }
        return []
    }
}

/// Sneak: held while pressed; a double-tap locks it until the next tap (Bedrock).
public struct SneakToggle: Equatable, Sendable {
    public static let doubleTap: TimeInterval = 0.3
    public private(set) var locked = false
    var lastRelease: TimeInterval = -1

    public init() {}

    /// Returns whether Shift should go down now.
    public mutating func press(time: TimeInterval) -> Bool {
        if locked { return false }
        return true
    }

    /// Returns whether Shift should go up now.
    public mutating func release(time: TimeInterval, pressedAt: TimeInterval) -> Bool {
        if locked {
            locked = false
            lastRelease = -1
            return true
        }
        let quick = time - pressedAt < Self.doubleTap
        if quick, lastRelease >= 0, pressedAt - lastRelease < Self.doubleTap {
            locked = true
            return false
        }
        lastRelease = quick ? time : -1
        return true
    }

    /// Minimal layout's swipe-down on jump.
    public mutating func toggle() -> Bool {
        locked.toggle()
        return locked
    }
}
