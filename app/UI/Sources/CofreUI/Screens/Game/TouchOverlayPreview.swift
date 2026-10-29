import SwiftUI

// The real overlay drawn over a stand-in game frame, for Settings tiles, PreviewHost screenshots and design review
// (`-screen touch -touch c|a|b|ipad|settings|sheet`). The stand-in HUD uses the same hotbar math as the overlay.

public enum TouchPreviewState: Sendable { case rest, active, tray, menu, flying, riding }

public enum TouchPreviewDevice: Sendable {
    case phone, pad

    var size: CGSize { self == .phone ? CGSize(width: 874, height: 402) : CGSize(width: 1210, height: 834) }
    /// Landscape safe area: Dynamic Island side and the home indicator.
    var insets: EdgeInsetsValue {
        self == .phone ? EdgeInsetsValue(left: 62, bottom: 21, right: 62) : EdgeInsetsValue(top: 24, bottom: 20)
    }
    var pixelsPerPoint: CGFloat { self == .phone ? 3 : 2 }
}

public struct TouchOverlayPreview: View {
    let device: TouchPreviewDevice
    @State private var model: TouchOverlayModel

    public init(
        style: TouchLayoutStyle = .dock, state: TouchPreviewState = .rest, device: TouchPreviewDevice = .phone,
        leftHanded: Bool = false
    ) {
        self.device = device
        _model = State(initialValue: Self.model(style: style, state: state, device: device, leftHanded: leftHanded))
    }

    @MainActor static func model(
        style: TouchLayoutStyle, state: TouchPreviewState, device: TouchPreviewDevice, leftHanded: Bool
    ) -> TouchOverlayModel {
        var s = TouchControlSettings()
        s.style = style
        s.leftHanded = leftHanded
        let m = TouchOverlayModel(input: nil, settings: s)
        m.insets = device.insets
        m.pixelsPerPoint = device.pixelsPerPoint
        m.screen = GameScreenState(inWorld: state != .menu)
        switch state {
        case .rest: m.idle = true
        case .active:
            let size = device.size
            let rest = m.frames(in: size)[.stick] ?? .zero
            m.stickCenter = style == .classic
                ? CGPoint(x: rest.midX, y: rest.midY)
                : CGPoint(x: rest.midX + (leftHanded ? -50 : 50), y: rest.midY - 30)
            m.knob = CGSize(width: 0, height: -rest.width * 0.295)
            m.stickKeys = [.w, .sprint]
            m.pressed = [.jump]
        case .tray:
            m.trayOpen = true
            m.context = .riding
        case .menu: break
        case .flying: m.context = .flying
        case .riding: m.context = .riding
        }
        return m
    }

    public var body: some View {
        ZStack {
            GameStandIn(screen: model.screen, hotbar: model.hotbar(in: device.size))
            TouchOverlayView(model: model)
        }
        .frame(width: device.size.width, height: device.size.height)
        .overlay { DeviceChrome(device: device) }
        .clipShape(RoundedRectangle(cornerRadius: device == .phone ? 56 : 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Stand-in game

/// PixelScene plus a Java-style HUD (hotbar, hearts, hunger, XP, crosshair) or an inventory screen.
struct GameStandIn: View {
    let screen: GameScreenState, hotbar: CGRect

    var body: some View {
        let g = hotbar.height / 22
        ZStack(alignment: .topLeading) {
            PixelScene(seed: 7, pixels: CGSize(width: 220, height: 100))
            if !screen.inWorld {
                Color.black.opacity(0.45)
                InventoryStandIn(g: g).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PixelArt(
                    ["...W...", "...W...", "...W...", "WWWWWWW", "...W...", "...W...", "...W..."],
                    palette: ["W": .white.opacity(0.9)], pixel: g * 1.3
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(width: hotbar.width)
                .position(x: hotbar.midX, y: hotbar.maxY - (22 + 2 + 3 + 2 + 8) * g / 2)
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

/// Rounded device corners plus the Dynamic Island on the leading side (landscape left), with safe-area guides.
struct DeviceChrome: View {
    let device: TouchPreviewDevice
    var body: some View {
        ZStack(alignment: .leading) {
            if device == .phone {
                Capsule().fill(Color.black).frame(width: 37, height: 126).padding(.leading, 11)
                HStack {
                    Rectangle().fill(Color.cofre.accent.opacity(0.08)).frame(width: device.insets.left)
                    Spacer()
                    Rectangle().fill(Color.cofre.accent.opacity(0.08)).frame(width: device.insets.right)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

// MARK: - Review pages

#if canImport(UIKit)
    /// PreviewHost entry (`-screen touch -touch c|a|b|ipad|settings|sheet`).
    public struct TouchControlsMockPage: View {
        let name: String
        public init(_ name: String) { self.name = name }

        public var body: some View {
            Group {
                switch name {
                case "sheet": TouchControlsSheet()
                case "settings": ControlsSettingsPage()
                case "ipad": TouchOverlayPreview(style: .dock, state: .active, device: .pad, leftHanded: true)
                case "a": strip([(.classic, .rest, "Classic · at rest"), (.classic, .flying, "Classic · flying")])
                case "b": strip([(.minimal, .rest, "Minimal · at rest"), (.minimal, .active, "Minimal · touching")])
                default:
                    strip([
                        (.dock, .rest, "Dock · at rest (35%)"), (.dock, .active, "Dock · moving + jump"),
                        (.dock, .tray, "Dock · riding, pause held: quick tray"),
                    ])
                }
            }
        }

        private func strip(_ frames: [(TouchLayoutStyle, TouchPreviewState, String)]) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(frames.indices, id: \.self) { i in
                    TouchOverlayPreview(style: frames[i].0, state: frames[i].1)
                    Text(verbatim: frames[i].2).cofreFont(.label).foregroundStyle(Color.cofre.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.cofre.page)
        }
    }

    /// The real Controls pane with mock services.
    struct ControlsSettingsPage: View {
        @State private var store = CofreStore(services: .mock())
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Controls").cofreFont(.header).foregroundStyle(Color.cofre.ink)
                    ControlsPane()
                }
                .padding(20)
            }
            .background(Color.cofre.page)
            .environment(store)
        }
    }

    /// Everything on one canvas for review.
    public struct TouchControlsSheet: View {
        public init() {}

        public var body: some View {
            let s: CGFloat = 0.6
            VStack(alignment: .leading, spacing: 16) {
                Text("Cofre · touch controls · built").cofreFont(.title).foregroundStyle(Color.cofre.ink)
                HStack(alignment: .top, spacing: 24) {
                    frame(.dock, .rest, s, "C Dock (default) · at rest, dimmed to 35%")
                    frame(.dock, .active, s, "C Dock · moving (sprint at the top edge) + jump held")
                    frame(.dock, .tray, s, "C Dock · riding, pause held: quick tray")
                }
                HStack(alignment: .top, spacing: 24) {
                    frame(.classic, .flying, s, "A Classic · flying (jump/sneak → fly up/down)")
                    frame(.minimal, .active, s, "B Minimal · stick under the thumb")
                    frame(.dock, .menu, s, "Any layout, in a menu: keyboard and close only")
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        TouchOverlayPreview(style: .dock, state: .active, device: .pad, leftHanded: true)
                            .scaleEffect(0.6, anchor: .topLeading)
                            .frame(width: 1210 * 0.6, height: 834 * 0.6, alignment: .topLeading)
                        Text("C on iPad, left-handed (mirrored), ×1.35 size").cofreFont(.label)
                            .foregroundStyle(Color.cofre.muted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ControlsSettingsPage().frame(width: 560, height: 700).clipped()
                            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                        Text("Settings → Controls").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.cofre.page)
        }

        private func frame(_ style: TouchLayoutStyle, _ state: TouchPreviewState, _ s: CGFloat, _ caption: String)
            -> some View
        {
            VStack(alignment: .leading, spacing: 6) {
                TouchOverlayPreview(style: style, state: state)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: 874 * s, height: 402 * s, alignment: .topLeading)
                Text(verbatim: caption).cofreFont(.label).foregroundStyle(Color.cofre.muted)
            }
        }
    }
#endif
