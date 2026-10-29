import XCTest

@testable import CofreUI

final class TouchControlsTests: XCTestCase {
    let phone = CGSize(width: 874, height: 402)
    let phoneInsets = EdgeInsetsValue(left: 62, bottom: 21, right: 62)

    // MARK: Fade (rule U4)

    func testFadesToIdleLevelAfterThreeSecondsUnlessHeld() {
        let s = TouchControlSettings()
        XCTAssertEqual(s.opacity, 0.8)
        XCTAssertEqual(s.opacity(idleFor: 2.9, holding: false), 0.8)
        XCTAssertEqual(s.opacity(idleFor: 3, holding: false), 0.35)
        XCTAssertEqual(s.opacity(idleFor: 60, holding: true), 0.8)
        var off = s
        off.fadeWhenIdle = false
        XCTAssertEqual(off.opacity(idleFor: 60, holding: false), 0.8)
        var faint = s
        faint.opacity = 0.25
        XCTAssertEqual(faint.opacity(idleFor: 60, holding: false), 0.25, "never brighter than the user's level")
    }

    func testDefaultsMatchTheSpec() {
        let s = TouchControlSettings()
        XCTAssertEqual(s.style, .dock)
        XCTAssertEqual(s.buttonScale, 1)
        XCTAssertTrue(s.fadeWhenIdle)
        XCTAssertTrue(s.haptics)
        XCTAssertFalse(s.leftHanded)
        XCTAssertFalse(s.invertY)
        XCTAssertEqual(s.lookSensitivity, 1)
    }

    func testSettingsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TouchControlsTests"))
        defaults.removePersistentDomain(forName: "TouchControlsTests")
        XCTAssertEqual(TouchControlSettings.load(defaults), TouchControlSettings())
        var s = TouchControlSettings()
        s.style = .minimal
        s.leftHanded = true
        s.opacity = 0.5
        s.save(defaults)
        XCTAssertEqual(TouchControlSettings.load(defaults), s)
    }

    func testLookDeltaAppliesSensitivityAndInvertY() {
        var s = TouchControlSettings()
        s.lookSensitivity = 2
        XCTAssertTrue(s.lookDelta(dx: 1, dy: 1, pixelsPerPoint: 3) == (6, 6))
        s.invertY = true
        XCTAssertTrue(s.lookDelta(dx: 1, dy: 1, pixelsPerPoint: 3) == (6, -6))
    }

    // MARK: Visibility by mode, screen and style (rules U1, U9, U10, U13)

    func testModeAndScreenDecideWhatShows() {
        let world = GameScreenState.world, menu = GameScreenState(inWorld: false)
        XCTAssertEqual(
            TouchLayout.controls(style: .dock, screen: world, mode: .touch),
            [.stick, .jump, .sneak, .pause, .chat, .inventory])
        XCTAssertEqual(TouchLayout.controls(style: .minimal, screen: world, mode: .touch), [.stick, .jump, .menu])
        XCTAssertEqual(TouchLayout.controls(style: .dock, screen: menu, mode: .touch), [.keyboard, .close])
        XCTAssertEqual(TouchLayout.controls(style: .dock, screen: world, mode: .controller), [])
        XCTAssertEqual(TouchLayout.controls(style: .dock, screen: menu, mode: .keyboardMouse), [])
        XCTAssertEqual(TouchLayout.controls(style: .dock, screen: world, mode: .touch, hudHidden: true), [.pause])
        XCTAssertEqual(TouchLayout.controls(style: .minimal, screen: world, mode: .touch, hudHidden: true), [.menu])
        for style in TouchLayoutStyle.allCases {
            XCTAssertLessThanOrEqual(TouchLayout.controls(style: style, screen: world, mode: .touch).count, 6)
        }
    }

    func testContextOnlySwapsGlyphs() {
        XCTAssertEqual(TouchLayout.jumpGlyph(.walking), .jump)
        XCTAssertEqual(TouchLayout.jumpGlyph(.flying), .flyUp)
        XCTAssertEqual(TouchLayout.jumpGlyph(.swimming), .swimUp)
        XCTAssertEqual(TouchLayout.sneakGlyph(.flying), .flyDown)
        XCTAssertEqual(TouchLayout.sneakGlyph(.swimming), .swimDown)
        XCTAssertEqual(TouchLayout.sneakGlyph(.riding), .dismount)
    }

    func testAutoModeFollowsLastInputUsed() {
        var t = CofreInputModeTracker(hasController: true)
        XCTAssertEqual(t.mode, .controller, "before any input, what's connected")
        t.used(.touch)
        XCTAssertEqual(t.mode, .touch, "a paired pad doesn't hide touch once the screen is touched")
        t.used(.controller)
        XCTAssertEqual(t.mode, .controller)
        t.hasController = false
        XCTAssertEqual(t.mode, .touch, "falls back when that device leaves")
        t.hasKeyboardOrMouse = true
        t.used(.keyboardMouse)
        XCTAssertEqual(t.mode, .keyboardMouse)
    }

    // MARK: Layout

    func testScaleClampsToWindowShortSide() {
        XCTAssertEqual(TouchLayout.scale(for: phone), 1)
        XCTAssertEqual(TouchLayout.scale(for: CGSize(width: 1210, height: 834)), 1.35)
        XCTAssertEqual(TouchLayout.scale(for: CGSize(width: 667, height: 375)), 1)
        XCTAssertEqual(TouchLayout.scale(for: phone, buttonScale: 1.5), 1.5)
    }

    func testHotbarUsesGameScaleOrMinecraftsAutoRule() {
        // 874×402 pt at 3× = 2622×1206 px → auto GUI scale 5 → 910×110 px.
        let auto = TouchLayout.hotbar(in: phone, screen: .world, defaultPixelsPerPoint: 3)
        XCTAssertEqual(auto.width, 910 / 3, accuracy: 0.01)
        XCTAssertEqual(auto.maxY, phone.height)
        XCTAssertEqual(auto.midX, phone.width / 2)
        let fixed = TouchLayout.hotbar(
            in: phone, screen: GameScreenState(inWorld: true, guiScale: 2, pixelsPerPoint: 2), defaultPixelsPerPoint: 3)
        XCTAssertEqual(fixed.width, 182)
        XCTAssertEqual(fixed.height, 22)
    }

    func testControlsStayInsideSafeAreaAndOffTheMiddle() {
        let hotbar = TouchLayout.hotbar(in: phone, screen: .world, defaultPixelsPerPoint: 3)
        for style in TouchLayoutStyle.allCases {
            let f = TouchLayout.frames(
                style: style, size: phone, insets: phoneInsets, scale: 1, leftHanded: false, hotbar: hotbar)
            let safe = CGRect(x: 62, y: 0, width: phone.width - 124, height: phone.height)
            let middle = CGRect(x: phone.width / 3, y: phone.height / 3, width: phone.width / 3, height: phone.height / 3)
            for c in TouchLayout.controls(style: style, screen: .world, mode: .touch) {
                let r = try! XCTUnwrap(f[c], "\(c)")
                XCTAssertTrue(safe.contains(r), "\(style) \(c) leaves the safe area")
                XCTAssertFalse(middle.intersects(r), "\(style) \(c) sits in the middle third")
            }
        }
    }

    func testLeftHandedMirrorsEverythingButTheHotbarDock() {
        let hotbar = TouchLayout.hotbar(in: phone, screen: .world, defaultPixelsPerPoint: 3)
        let right = TouchLayout.frames(
            style: .dock, size: phone, insets: phoneInsets, scale: 1, leftHanded: false, hotbar: hotbar)
        let left = TouchLayout.frames(
            style: .dock, size: phone, insets: phoneInsets, scale: 1, leftHanded: true, hotbar: hotbar)
        for c in [TouchControl.stick, .jump, .sneak, .pause] {
            XCTAssertEqual(left[c]!.minX, phone.width - right[c]!.maxX, accuracy: 0.001, "\(c)")
            XCTAssertEqual(left[c]!.minY, right[c]!.minY)
        }
        XCTAssertEqual(left[.chat], right[.chat])
        XCTAssertEqual(left[.inventory], right[.inventory])
        XCTAssertLessThan(right[.stick]!.midX, phone.width / 2)
        XCTAssertGreaterThan(left[.stick]!.midX, phone.width / 2)
        XCTAssertEqual(TouchLayout.stickZone(size: phone, leftHanded: true).maxX, phone.width)
    }

    func testHitTargetsAreAtLeast44Points() {
        let small = TouchLayout.hitRect(CGRect(x: 100, y: 100, width: 36, height: 36))
        XCTAssertEqual(small.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(small.midX, 118)
        let big = CGRect(x: 0, y: 0, width: 60, height: 60)
        XCTAssertEqual(TouchLayout.hitRect(big), big)
    }

    // MARK: Gestures

    func testStickMapsToKeysWithSprintAtTheTopEdge() {
        XCTAssertEqual(StickKeys.keys(dx: 0, dy: -5, radius: 50), [], "dead zone")
        XCTAssertEqual(StickKeys.keys(dx: 0, dy: -30, radius: 50), [.w])
        XCTAssertEqual(StickKeys.keys(dx: 0, dy: -50, radius: 50), [.w, .sprint])
        XCTAssertEqual(StickKeys.keys(dx: 30, dy: -30, radius: 50), [.w, .d])
        XCTAssertEqual(StickKeys.keys(dx: -40, dy: 0, radius: 50), [.a])
        XCTAssertEqual(StickKeys.keys(dx: 0, dy: 40, radius: 50), [.s])
    }

    func testWorldTouchTapUsesHoldAttacksDragLooks() {
        var tap = WorldTouch(at: .zero, time: 0)
        XCTAssertEqual(tap.end(time: 0.1), [.use])

        var hold = WorldTouch(at: .zero, time: 0)
        XCTAssertEqual(hold.tick(time: 0.1), [])
        XCTAssertEqual(hold.tick(time: 0.3), [.attackDown])
        XCTAssertEqual(hold.move(to: CGPoint(x: 20, y: 0), time: 0.5), [.look(dx: 20, dy: 0)], "keeps breaking while looking")
        XCTAssertEqual(hold.end(time: 0.8), [.attackUp])

        var drag = WorldTouch(at: .zero, time: 0)
        XCTAssertEqual(drag.move(to: CGPoint(x: 4, y: 0), time: 0.05), [], "under the slop")
        XCTAssertEqual(drag.move(to: CGPoint(x: 12, y: 0), time: 0.1), [.look(dx: 12, dy: 0)])
        XCTAssertEqual(drag.tick(time: 1), [], "a look never turns into a break")
        XCTAssertEqual(drag.end(time: 1.2), [])
    }

    func testSneakDoubleTapLocksAndNextTapUnlocks() {
        var s = SneakToggle()
        XCTAssertTrue(s.press(time: 0))
        XCTAssertTrue(s.release(time: 0.1, pressedAt: 0), "single tap releases")
        XCTAssertTrue(s.press(time: 0.2))
        XCTAssertFalse(s.release(time: 0.25, pressedAt: 0.2), "second quick tap keeps Shift down")
        XCTAssertTrue(s.locked)
        XCTAssertFalse(s.press(time: 2))
        XCTAssertTrue(s.release(time: 2.1, pressedAt: 2))
        XCTAssertFalse(s.locked)
        var held = SneakToggle()
        _ = held.press(time: 0)
        XCTAssertTrue(held.release(time: 1, pressedAt: 0), "a long hold just releases")
    }

    // MARK: Overlay model

    @MainActor
    func testButtonsSendKeys() {
        let spy = SpyInput()
        let m = TouchOverlayModel(input: spy, settings: TouchControlSettings())
        m.buttonDown(.jump)
        m.buttonUp(.jump)
        m.buttonDown(.inventory)
        m.buttonUp(.inventory)
        m.buttonDown(.pause)
        m.buttonUp(.pause)
        XCTAssertEqual(spy.events, ["touch", "+SPACE", "-SPACE", "touch", "+E", "-E", "touch", "+ESC", "-ESC"])
    }

    @MainActor
    func testQuickTrayHideHUDTogglesF1AndLeavesOnlyPause() {
        let spy = SpyInput()
        let m = TouchOverlayModel(input: spy, settings: TouchControlSettings())
        m.trayOpen = true
        m.select(.hideHUD)
        XCTAssertFalse(m.trayOpen)
        XCTAssertTrue(m.hudHidden)
        XCTAssertEqual(m.controls, [.pause])
        XCTAssertEqual(m.opacity, 0.3)
        XCTAssertTrue(spy.events.contains("+F1"))
    }

    @MainActor
    func testHitTestingPassesTheHotbarAndMenusThrough() {
        let m = TouchOverlayModel(input: nil, settings: TouchControlSettings())
        m.insets = phoneInsets
        m.pixelsPerPoint = 3
        let hotbar = m.hotbar(in: phone)
        XCTAssertFalse(m.captures(CGPoint(x: hotbar.midX, y: hotbar.midY), in: phone), "hotbar taps reach the game")
        XCTAssertTrue(m.captures(CGPoint(x: phone.width / 2, y: phone.height / 2), in: phone), "the world is ours")
        m.screen = GameScreenState(inWorld: false)
        XCTAssertFalse(m.captures(CGPoint(x: phone.width / 2, y: phone.height / 2), in: phone), "menus go to the game")
        let close = m.frames(in: phone)[.close]!
        XCTAssertTrue(m.captures(CGPoint(x: close.midX, y: close.midY), in: phone))
        m.screen = .world
        m.mode = .controller
        XCTAssertFalse(m.captures(CGPoint(x: phone.width / 2, y: phone.height / 2), in: phone))
    }

    @MainActor
    func testLeavingTouchModeReleasesHeldKeys() {
        let spy = SpyInput()
        let m = TouchOverlayModel(input: spy, settings: TouchControlSettings())
        m.buttonDown(.jump)
        m.setMode(.controller)
        XCTAssertEqual(spy.events.last, "-SPACE")
        XCTAssertTrue(m.controls.isEmpty)
    }
}

private final class SpyInput: GameInputService {
    var events: [String] = []
    func press(_ key: CofreInputKey) { events.append("+\(key.rawValue)") }
    func release(_ key: CofreInputKey) { events.append("-\(key.rawValue)") }
    func noteTouchInput() { events.append("touch") }
}
