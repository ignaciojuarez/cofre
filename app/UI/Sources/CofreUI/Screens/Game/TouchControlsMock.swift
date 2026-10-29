import SwiftUI

// Design mock only (plan/touch-controls.md): three touch-control variations drawn over a stand-in game frame, plus
// the Controls settings pane. Nothing here talks to the game. Phase 2 replaces it with the real overlay.

public enum TouchMockVariant: String, CaseIterable, Sendable {
    case bedrock, ghost, dock

    var title: String {
        switch self {
        case .bedrock: "A · Bedrock"
        case .ghost: "B · Ghost"
        case .dock: "C · Dock"
        }
    }
}

public enum TouchMockState: String, Sendable {
    /// In the world, nothing touched for a while.
    case idle
    /// Left thumb moving (sprinting), right thumb looking.
    case active
    case flying
    /// In an inventory screen: world controls hide, touches drive the pointer.
    case menu
    /// C, riding, with the quick tray held open from the pause button.
    case radial
}

public enum TouchMockDevice: Sendable {
    case phone, pad

    var size: CGSize { self == .phone ? CGSize(width: 874, height: 402) : CGSize(width: 1210, height: 834) }
    /// Landscape safe area: Dynamic Island side and the home indicator.
    var insets: EdgeInsets {
        self == .phone
            ? EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
            : EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
    }
    /// Control scale: short side / 402, clamped (rule U6).
    var k: CGFloat { min(max(size.height / 402, 1), 1.35) }
    /// Minecraft GUI pixels → points, so the stand-in HUD matches an auto GUI scale.
    var gui: CGFloat { self == .phone ? 1.6 : 2.4 }
}

// MARK: - One frame

public struct TouchControlsMock: View {
    let variant: TouchMockVariant, state: TouchMockState, device: TouchMockDevice, leftHanded: Bool

    public init(
        _ variant: TouchMockVariant, state: TouchMockState = .idle, device: TouchMockDevice = .phone,
        leftHanded: Bool = false
    ) {
        self.variant = variant
        self.state = state
        self.device = device
        self.leftHanded = leftHanded
    }

    public var body: some View {
        let size = device.size
        ZStack {
            GameStandIn(device: device, crosshair: state != .menu, menu: state == .menu)
            controls
                .padding(device.insets)
                // Left-handed mirrors positions only; glyphs stay readable.
                .environment(\.layoutDirection, leftHanded ? .rightToLeft : .leftToRight)
        }
        .frame(width: size.width, height: size.height)
        .overlay { DeviceChrome(device: device) }
        .clipShape(RoundedRectangle(cornerRadius: device == .phone ? 56 : 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var controls: some View {
        let k = device.k
        let hotbar = CGSize(width: 182 * device.gui, height: 22 * device.gui)
        let idleFade = state == .idle
        switch (variant, state) {
        case (_, .menu):
            // Every variant: world controls hide while a screen is open. Keyboard and close, top trailing.
            corner(.topTrailing) {
                HStack(spacing: 8) {
                    OverlayButton(.keyboard, size: 40 * k)
                    OverlayButton(.close, size: 40 * k)
                }
            }.padding(.top, 10)
        case (.bedrock, _):
            ZStack {
                corner(.bottomLeading) { Joystick(k: k, push: state == .active ? 1 : 0) }
                    .padding(.leading, 16).padding(.bottom, 14)
                corner(.bottomTrailing) {
                    HStack(alignment: .bottom, spacing: 12 * k) {
                        OverlayButton(state == .flying ? .flyDown : .sneak, size: 52 * k)
                        OverlayButton(state == .flying ? .flyUp : .jump, size: 60 * k)
                    }
                }.padding(.trailing, 16).padding(.bottom, 14)
                corner(.topTrailing) {
                    HStack(spacing: 8) {
                        OverlayButton(.chat, size: 40 * k)
                        OverlayButton(.pause, size: 40 * k)
                    }
                }.padding(.top, 10)
                hotbarDots(hotbar: hotbar)
            }.opacity(0.8)
        case (.ghost, _):
            ZStack {
                if state == .active {
                    // Floating stick: appears under the thumb, nothing drawn at rest.
                    corner(.bottomLeading) { Joystick(k: k, push: 1, floating: true) }
                        .padding(.leading, 70).padding(.bottom, 40)
                }
                corner(.bottomTrailing) {
                    OverlayButton(state == .flying ? .flyUp : .jump, size: 60 * k, hint: "▼ sneak")
                }.padding(.trailing, 16).padding(.bottom, 14)
                corner(.topTrailing) { OverlayButton(.menu, size: 36 * k) }.padding(.top, 10)
            }
            .opacity(idleFade ? 0.35 : 0.8)
        case (.dock, _):
            ZStack {
                corner(.bottomLeading) { Joystick(k: k, push: state == .active ? 1 : 0, ghostBase: idleFade) }
                    .padding(.leading, 16).padding(.bottom, 14)
                corner(.bottomTrailing) {
                    ZStack(alignment: .bottomTrailing) {
                        OverlayButton(state == .flying ? .flyUp : .jump, size: 60 * k)
                        OverlayButton(
                            state == .flying ? .flyDown : (state == .radial ? .dismount : .sneak), size: 46 * k,
                            label: state == .radial ? "Dismount" : nil
                        )
                        .offset(x: -64 * k, y: -34 * k)
                    }
                }.padding(.trailing, 16).padding(.bottom, 14)
                corner(.topTrailing) {
                    OverlayButton(.pause, size: 36 * k, on: state == .radial)
                        .overlay(alignment: .topTrailing) {
                            if state == .radial { QuickTray(k: k).fixedSize().offset(y: 36 * k + 8) }
                        }
                }.padding(.top, 10)
                hotbarDock(hotbar: hotbar)
            }
            .opacity(idleFade ? 0.35 : 0.8)
        }
    }

    private func corner<C: View>(_ a: Alignment, @ViewBuilder _ c: () -> C) -> some View {
        ZStack(alignment: a) {
            Color.clear
            c()
        }
    }

    /// Bedrock's "•••" inventory button, flush with the hotbar's trailing end.
    private func hotbarDots(hotbar: CGSize) -> some View {
        corner(.bottom) {
            HStack(spacing: 2) {
                Color.clear.frame(width: hotbar.width, height: hotbar.height)
                OverlayButton(.dots, size: hotbar.height, flat: true)
            }.offset(x: (hotbar.height + 2) / 2)
        }.padding(.bottom, 2)
    }

    /// C: chat and inventory dock on the hotbar's two ends, so the play area stays clear.
    private func hotbarDock(hotbar: CGSize) -> some View {
        corner(.bottom) {
            HStack(spacing: 2) {
                OverlayButton(.chat, size: hotbar.height, flat: true)
                Color.clear.frame(width: hotbar.width, height: hotbar.height)
                OverlayButton(.dots, size: hotbar.height, flat: true)
            }
        }.padding(.bottom, 2)
    }
}

// MARK: - Controls

enum OverlayGlyph {
    case jump, sneak, flyUp, flyDown, chat, pause, dots, menu, close, keyboard, dismount, eye, players, drop, swap,
        hide

    var rows: [String] {
        switch self {
        case .jump: ["...W...", "..WWW..", ".WWWWW.", "WWWWWWW", "..WWW..", "..WWW..", "..WWW.."]
        case .sneak: ["..WWW..", "..WWW..", "..WWW..", "WWWWWWW", ".WWWWW.", "..WWW..", "WWWWWWW"]
        case .flyUp: ["...W...", "..WWW..", ".WW.WW.", "WW...WW", "...W...", "..WWW..", ".WW.WW.", "WW...WW"]
        case .flyDown: ["WW...WW", ".WW.WW.", "..WWW..", "...W...", "WW...WW", ".WW.WW.", "..WWW..", "...W..."]
        case .chat: ["WWWWWWW", "W.....W", "W.W.W.W", "W.....W", "WWWWWWW", ".WW....", ".W....."]
        case .pause: ["WW.WW", "WW.WW", "WW.WW", "WW.WW", "WW.WW", "WW.WW", "WW.WW"]
        case .dots: ["WW.WW.WW", "WW.WW.WW"]
        case .menu: ["WWWWWWW", ".......", "WWWWWWW", ".......", "WWWWWWW"]
        case .close: ["W.....W", ".W...W.", "..W.W..", "...W...", "..W.W..", ".W...W.", "W.....W"]
        case .keyboard: ["WWWWWWWWW", "W.W.W.W.W", "WWWWWWWWW", "W.W.W.W.W", "WWWWWWWWW", "W..WWW..W", "WWWWWWWWW"]
        case .dismount: ["WWWW...", "W......", "W..W...", "W..WW..", "W..WWWW", "W..WW..", "WWWWW.."]
        case .eye: [".WWWWW.", "W.....W", "W..W..W", "W.WWW.W", "W..W..W", "W.....W", ".WWWWW."]
        case .players: [".W...W.", "WWW.WWW", ".W...W.", ".......", "WWW.WWW", "WWW.WWW"]
        case .drop: ["..WWW..", "..WWW..", "WWWWWWW", ".WWWWW.", "..WWW..", "...W...", "WWWWWWW"]
        case .swap: ["..W....", ".WWWWWW", "..W...W", ".......", "W...W..", "WWWWWW.", "....W.."]
        case .hide: ["W.....W", ".WWWWW.", "W.W.W.W", "W.WWW.W", "W.W.W.W", ".WWWWW.", "W.....W"]
        }
    }
}

/// Translucent square control in Cofre's block style: dark glass fill, light outline, pixel glyph.
struct OverlayButton: View {
    let glyph: OverlayGlyph, size: CGFloat
    var on = false, flat = false
    var hint: String?, label: String?

    init(
        _ glyph: OverlayGlyph, size: CGFloat, on: Bool = false, flat: Bool = false, hint: String? = nil,
        label: String? = nil
    ) {
        self.glyph = glyph
        self.size = size
        self.on = on
        self.flat = flat
        self.hint = hint
        self.label = label
    }

    var body: some View {
        let px = max(2, (size * 0.5 / CGFloat(glyph.rows.first?.count ?? 7)).rounded(.down))
        VStack(spacing: 3) {
            ZStack {
                Rectangle().fill(on ? Color.cofre.face.opacity(0.9) : Color.black.opacity(flat ? 0.55 : 0.4))
                if !flat {
                    Color.white.opacity(0.14).frame(height: 2).padding([.horizontal, .top], 2)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Color.black.opacity(0.35).frame(height: 3).padding([.horizontal, .bottom], 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                Rectangle().strokeBorder(Color.white.opacity(flat ? 0.25 : 0.5), lineWidth: 2)
                PixelArt(glyph.rows, palette: ["W": Color.cofre.ink], pixel: px)
            }
            .frame(width: size, height: size)
            if let hint {
                Text(verbatim: hint).font(.cofre(.label)).foregroundStyle(Color.white.opacity(0.6))
            }
            if let label {
                Text(verbatim: label).font(.cofre(.chip)).foregroundStyle(Color.cofre.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.5))
            }
        }
    }
}

/// Square stick: a well with a beveled knob. `push` 1 = pushed to the top edge, which sprints.
struct Joystick: View {
    let k: CGFloat
    var push: CGFloat = 0, floating = false, ghostBase = false

    var body: some View {
        let base = 112 * k, knob = 46 * k
        ZStack {
            Rectangle().fill(Color.black.opacity(ghostBase ? 0.1 : 0.25))
            Rectangle().strokeBorder(Color.white.opacity(ghostBase ? 0.22 : 0.4), lineWidth: 2)
            if push > 0.9 {
                // Sprint zone lit along the top edge.
                Color.cofre.accent.frame(height: 4).frame(maxHeight: .infinity, alignment: .top).padding(2)
                Text(verbatim: "SPRINT").font(.cofre(.label)).foregroundStyle(Color.cofre.accent)
                    .offset(y: -base / 2 - 12)
            }
            ZStack {
                Rectangle().fill(Color.white.opacity(0.3))
                Color.white.opacity(0.3).frame(height: 2).padding([.horizontal, .top], 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
            }
            .frame(width: knob, height: knob)
            .offset(y: -push * (base - knob) / 2)
        }
        .frame(width: base, height: base)
        .overlay(alignment: .bottom) {
            if floating {
                Text(verbatim: "appears under your thumb").font(.cofre(.label))
                    .foregroundStyle(Color.white.opacity(0.7)).fixedSize().offset(y: 20)
            }
        }
    }
}

    /// C's quick tray: hold the pause button (or swipe down from it) for the rarer actions. Tap still pauses.
struct QuickTray: View {
    let k: CGFloat
    var body: some View {
        let items: [(OverlayGlyph, String)] = [
            (.eye, "View"), (.players, "Players"), (.drop, "Drop"), (.swap, "Swap hands"), (.hide, "Hide HUD"),
            (.keyboard, "Keyboard"),
        ]
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { col in
                        let i = row * 3 + col
                        VStack(spacing: 3) {
                            OverlayButton(items[i].0, size: 40 * k, on: i == 0)
                            Text(verbatim: items[i].1).font(.cofre(.label)).foregroundStyle(Color.cofre.ink).fixedSize()
                        }
                        .frame(width: 64 * k)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .overlay { Rectangle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2) }
    }
}

// MARK: - Stand-in game

/// PixelScene plus a Java-style HUD (hotbar, hearts, hunger, XP, crosshair) at an auto GUI scale.
struct GameStandIn: View {
    let device: TouchMockDevice, crosshair: Bool, menu: Bool

    var body: some View {
        let g = device.gui
        ZStack {
            PixelScene(seed: 7, pixels: CGSize(width: 220, height: 100))
            if menu {
                Color.black.opacity(0.45)
                InventoryStandIn(g: g)
            } else {
                if crosshair {
                    PixelArt(["...W...", "...W...", "...W...", "WWWWWWW", "...W...", "...W...", "...W..."],
                             palette: ["W": .white.opacity(0.9)], pixel: g * 1.3)
                }
                VStack(spacing: 2 * g) {
                    HStack(spacing: 0) {
                        HStack(spacing: g) { ForEach(0..<10, id: \.self) { _ in Heart(g: g) } }
                        Spacer()
                        HStack(spacing: g) { ForEach(0..<10, id: \.self) { _ in Food(g: g) } }
                    }
                    Rectangle().fill(Color.black.opacity(0.6)).frame(height: 3 * g)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(red: 0.5, green: 0.95, blue: 0.2)).frame(width: 110 * g)
                        }
                    Hotbar(g: g)
                }
                .frame(width: 182 * g)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, device.insets.bottom + 2)
            }
        }
    }
}

struct Hotbar: View {
    let g: CGFloat
    var body: some View {
        let items: [PixelGlyph?] = [.grass, .planks, .cobble, .log, .ore, nil, .sand, .bricks, nil]
        HStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { i in
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.5))
                    Rectangle().strokeBorder(Color(white: 0.35), lineWidth: g)
                    if let glyph = items[i] { PixelIcon(glyph, size: 14 * g) }
                }
                .frame(width: 20 * g, height: 20 * g)
                .overlay { if i == 0 { Rectangle().strokeBorder(Color.white, lineWidth: 2 * g).padding(-g) } }
            }
        }
        .padding(g)
        .background(Color(white: 0.2).opacity(0.8))
    }
}

struct Heart: View {
    let g: CGFloat
    var body: some View {
        PixelArt([".R.R.", "RRRRR", "RRRRR", ".RRR.", "..R.."], palette: ["R": Color(red: 0.86, green: 0.1, blue: 0.1)],
                 pixel: g * 1.6)
    }
}

struct Food: View {
    let g: CGFloat
    var body: some View {
        PixelArt(["...BB", "..BBB", ".BBB.", "WBB..", "W...."],
                 palette: ["B": Color(red: 0.62, green: 0.38, blue: 0.18), "W": .white], pixel: g * 1.6)
    }
}

/// A gray Minecraft container screen with a pointer, for the "menu" state.
struct InventoryStandIn: View {
    let g: CGFloat
    var body: some View {
        VStack(spacing: 4 * g) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { col in
                        Rectangle().fill(Color(white: 0.55))
                            .overlay { Rectangle().strokeBorder(Color(white: 0.35), lineWidth: g) }
                            .overlay { if row == 3 && col < 5 { PixelIcon([.grass, .planks, .cobble, .log, .ore][col], size: 12 * g) } }
                            .frame(width: 18 * g, height: 18 * g)
                    }
                }
                .padding(.top, row == 3 ? 4 * g : 0)
            }
        }
        .padding(7 * g)
        .background(Color(white: 0.78))
        .overlay { Rectangle().strokeBorder(Color.white, lineWidth: g) }
        .overlay(alignment: .topLeading) {
            Circle().fill(Color.white.opacity(0.25)).frame(width: 34, height: 34).offset(x: 72 * g, y: 52 * g)
        }
    }
}

/// Rounded device corners plus the Dynamic Island on the leading side (landscape left).
struct DeviceChrome: View {
    let device: TouchMockDevice
    var body: some View {
        ZStack(alignment: .leading) {
            if device == .phone {
                Capsule().fill(Color.black).frame(width: 37, height: 126).padding(.leading, 11)
                // Safe-area guides (mock only).
                HStack {
                    Rectangle().fill(Color.cofre.accent.opacity(0.08)).frame(width: device.insets.leading)
                    Spacer()
                    Rectangle().fill(Color.cofre.accent.opacity(0.08)).frame(width: device.insets.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

// MARK: - Settings → Controls (mock)

public struct ControlsSettingsMock: View {
    @State private var mode = "auto"
    @State private var layout = TouchMockVariant.dock
    @State private var size = 1.0
    @State private var opacity = 0.8
    @State private var sensitivity = 1.0
    @State private var fade = true
    @State private var leftHanded = false
    @State private var haptics = true
    @State private var invertY = false
    @State private var gyro = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Controls").cofreFont(.header).foregroundStyle(Color.cofre.ink)
                ListSection("Input", spacing: 4) {
                    Segmented(
                        "Input", selection: $mode,
                        options: [("auto", "Auto"), ("touch", "Touch"), ("pad", "Controller"), ("kbm", "Keyboard & mouse")])
                    Text("Auto switches to a controller or keyboard the moment you use one, and back to touch when you touch the screen.")
                        .cofreFont(.label).foregroundStyle(Color.cofre.muted).padding(.horizontal, 2)
                    Row("Using now", subtitle: "Touch · DualSense paired, press any button") {
                        PixelIcon(.cmd, size: 20)
                    } trailing: { Badge("Auto", tone: .accent) }
                }
                ListSection("Touch layout", spacing: 4) {
                    HStack(spacing: 6) {
                        ForEach(TouchMockVariant.allCases, id: \.self) { v in
                            VStack(spacing: 6) {
                                TouchControlsMock(v, state: v == .ghost ? .active : .idle).scaleEffect(0.19)
                                    .frame(width: 874 * 0.19, height: 402 * 0.19)
                                Text(verbatim: v.title).cofreFont(.chip).foregroundStyle(Color.cofre.ink)
                            }
                            .padding(6)
                            .block(.panel, selected: v == layout)
                            .overlay { if v == layout { Rectangle().strokeBorder(Color.cofre.accent, lineWidth: 2) } }
                        }
                    }
                }
                ListSection("Touch", spacing: 4) {
                    BlockSlider("Button size", value: $size, in: 0.6...1.5, step: 0.05) { "\(Int($0 * 100)) %" }
                    BlockSlider("Opacity", value: $opacity, in: 0.2...1, step: 0.05) { "\(Int($0 * 100)) %" }
                    ToggleRow("Fade when idle", subtitle: "Dims to 35% after 3 s", isOn: $fade)
                    ToggleRow("Left-handed", subtitle: "Mirror stick and buttons", isOn: $leftHanded)
                    ToggleRow("Haptics", isOn: $haptics)
                    BlockButton("Edit layout", icon: .cmd) {}
                }
                ListSection("Look", spacing: 4) {
                    BlockSlider("Look sensitivity", value: $sensitivity, in: 0.25...3, step: 0.05) {
                        String(format: "%.2f×", $0)
                    }
                    ToggleRow("Invert Y", isOn: $invertY)
                    ToggleRow("Gyro aim", subtitle: "Fine-tune aim by tilting", isOn: $gyro)
                }
            }
            .padding(20)
        }
        .background(Color.cofre.page)
    }
}

// MARK: - Contact sheet

/// Everything on one canvas for review: each variant at rest and in context, iPad, settings.
public struct TouchControlsSheet: View {
    public init() {}

    public var body: some View {
        let s: CGFloat = 0.72
        VStack(alignment: .leading, spacing: 18) {
            Text("Cofre · touch controls · 3 variations").cofreFont(.title).foregroundStyle(Color.cofre.ink)
            HStack(alignment: .top, spacing: 24) {
                ForEach(TouchMockVariant.allCases, id: \.self) { v in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(verbatim: v.title).cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                            if v == .dock { Badge("Recommended", tone: .success) }
                        }
                        scaled(TouchControlsMock(v, state: v == .ghost ? .idle : .idle), s, caption: "At rest")
                        scaled(TouchControlsMock(v, state: Self.context(v)), s, caption: Self.contextCaption(v))
                        ForEach(Self.notes(v), id: \.self) { n in
                            Text(verbatim: "• " + n).cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 874 * s)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                scaled(TouchControlsMock(.dock, state: .active, device: .pad), 0.5,
                       caption: "C on iPad: ×1.35 size, same corners")
                scaled(TouchControlsMock(.ghost, state: .menu), s, caption: "Any variant, in a menu: ✕ and keyboard only")
                VStack(alignment: .leading, spacing: 6) {
                    ControlsSettingsMock().frame(width: 560, height: 640).clipped()
                        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                    Text(verbatim: "Settings → Controls").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cofre.page)
    }

    private func scaled<V: View>(_ v: V, _ s: CGFloat, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            v.scaleEffect(s, anchor: .topLeading)
                .frame(width: Self.size(of: v).width * s, height: Self.size(of: v).height * s, alignment: .topLeading)
            Text(verbatim: caption).cofreFont(.label).foregroundStyle(Color.cofre.muted)
        }
    }

    private static func size<V: View>(of v: V) -> CGSize {
        (v as? TouchControlsMock)?.device.size ?? .zero
    }

    static func context(_ v: TouchMockVariant) -> TouchMockState {
        switch v {
        case .bedrock: .flying
        case .ghost: .active
        case .dock: .radial
        }
    }

    static func contextCaption(_ v: TouchMockVariant) -> String {
        switch v {
        case .bedrock: "Flying: jump/sneak become fly up/down"
        case .ghost: "Touching: controls at full, stick under thumb"
        case .dock: "Riding: sneak becomes Dismount · pause held: quick tray"
        }
    }

    static func notes(_ v: TouchMockVariant) -> [String] {
        switch v {
        case .bedrock:
            [
                "6 visible: stick, jump, sneak, chat, pause, •••", "No idle fade; 80% opacity",
                "Zero learning for Bedrock players; busiest screen",
            ]
        case .ghost:
            [
                "2 visible: jump, ≡. Stick only under the thumb", "Sneak = swipe down on jump; inventory = swipe up on hotbar",
                "Cleanest; hidden gestures cost discoverability",
            ]
        case .dock:
            [
                "Bedrock positions, 4 clusters: stick, jump+sneak, pause, hotbar dock (chat · •••)",
                "Dims to 35% after 3 s; hold pause for a quick tray of extras", "Familiar and quiet; our pick",
            ]
        }
    }
}

#Preview("Sheet") { TouchControlsSheet().frame(width: 1960, height: 1480) }
#Preview("Settings") { ControlsSettingsMock() }

/// PreviewHost entry (`-screen touch -touch a|b|c|ipad|settings|sheet`). Per-variant pages stack rest over context.
public struct TouchControlsMockPage: View {
    let name: String
    public init(_ name: String) { self.name = name }

    public var body: some View {
        Group {
            switch name {
            case "sheet": TouchControlsSheet()
            case "settings": ControlsSettingsMock()
            case "ipad": TouchControlsMock(.dock, state: .active, device: .pad)
            default:
                let v: TouchMockVariant = name == "a" ? .bedrock : name == "b" ? .ghost : .dock
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: v.title).cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                    TouchControlsMock(v, state: .idle)
                    Text(verbatim: "At rest").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    TouchControlsMock(v, state: TouchControlsSheet.context(v))
                    Text(verbatim: TouchControlsSheet.contextCaption(v)).cofreFont(.label)
                        .foregroundStyle(Color.cofre.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.cofre.page)
            }
        }
    }
}
