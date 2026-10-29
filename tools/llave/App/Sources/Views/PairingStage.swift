import CofreUI
import SwiftUI

/// The big pixel illustration: a Mac and an iPhone on Cofre's moonlit lake scene, one pose per step.
/// The scene and every sprite share one 4 pt grid. Motion steps like the Spinner and stops under Reduce Motion.
struct PairingStage: View {
    let art: StateScreen.Art
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 520, height: 264)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let t = reduceMotion ? nil : Int(ctx.date.timeIntervalSinceReferenceDate * 4)
            ZStack(alignment: .topLeading) {
                PixelScene(seed: 7, pixels: CGSize(width: 130, height: 66))
                    .frame(width: Self.size.width, height: Self.size.height)
                pose(t).offset(x: 3 * u, y: 7 * u) // centered, standing on the scene's ground
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .top) { titleBar }
    }

    /// Cofre's mark, centered in the hidden title bar next to the window buttons.
    private var titleBar: some View {
        HStack(spacing: 8) {
            AppIcon(size: 18)
            Text(verbatim: "Cofre").cofreFont(.headerCompact).foregroundStyle(.white).shadow(color: .black, radius: 0, y: 2)
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    // `t` is the animation step, nil under Reduce Motion (each pose then holds one clear frame).
    @ViewBuilder private func pose(_ t: Int?) -> some View {
        switch art {
        case .plugIn:
            Self.mac(at: 8, t)
            Self.cable(macAt: 8, to: [105], gap: t.map { [3, 2, 1, 2][$0 % 4] } ?? 2)
            Self.phone(at: 96, .off, t)
        case .pick:
            Self.mac(at: 4, t)
            Self.cable(macAt: 4, to: [79, 107])
            Self.phone(at: 70, .owner, t)
            Self.phone(at: 98, .owner, t)
        case .unlock:
            connected(.unlock, t)
        case .trust:
            connected(.trust, t)
        case .connecting:
            connected(.spinner, t, flow: true)
        case .placing:
            Self.mac(at: 8, t)
            Self.cable(macAt: 8, to: [105], flow: t)
            PixelIcon(.key, size: 40).offset(x: CGFloat(64 + (t.map { $0 * 2 % 30 } ?? 14)) * 4, y: 172 - CGFloat((t ?? 0) % 2) * 4)
            Self.phone(at: 96, .chest, t)
        case .done:
            connected(.done, t)
            Self.sparkles(t)
        case .missing:
            connected(.missing, t)
        case .airDrop:
            Self.mac(at: 8, t)
            PixelArt(Self.arcs, palette: Self.arcColors(t)).at(70, 26)
            Self.phone(at: 96, .key, t)
        case .problem:
            connected(.cross, t)
        }
    }

    @ViewBuilder private func connected(_ screen: PhoneScreen, _ t: Int?, flow: Bool = false) -> some View {
        Self.mac(at: 8, t)
        Self.cable(macAt: 8, to: [105], flow: flow ? t : nil)
        Self.phone(at: 96, screen, t)
    }
}

// MARK: - Sprites

private let u: CGFloat = 4

private extension View {
    /// Places a sprite at art-pixel coordinates on the stage.
    func at(_ x: Int, _ y: Int) -> some View { offset(x: CGFloat(x) * u, y: CGFloat(y) * u) }
}

/// Solid art pixels (cable, cursor, sparkles).
private func px(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: Color) -> some View {
    color.frame(width: CGFloat(w) * u, height: CGFloat(h) * u).at(x, y)
}

enum PhoneScreen { case off, owner, unlock, trust, spinner, chest, done, missing, key, cross }

extension PairingStage {
    static let palette: [Character: Color] = [
        "o": .cofre.outline, "k": .cofre.side, "n": .cofre.well, "w": .cofre.ink, "s": .cofre.inkSoft, "m": .cofre.muted,
        "g": .cofre.success, "Y": .cofre.warn, "P": .cofre.button, "B": .cofre.buttonBevel, "F": .cofre.face, "f": .cofre.faceBevel,
    ]

    /// MacBook, lid open on Terminal, 52×33.
    static let macArt: [String] = [
        ".....oooooooooooooooooooooooooooooooooooooooooo.....",
        "....oowwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwoo....",
        "....oskkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnggnssssnsssssssssnssnssnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnmmmmmmmmmmmmmmmmmmnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnmmmmmmmmmmmmmmmmmmmmmmmmnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnmmmmmmmmmmmmmmnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnggnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....osknnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnkso....",
        "....oskkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkso....",
        "....oskkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkso....",
        "....oskkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkso....",
        "....oooooooooooooooooooooooooooooooooooooooooooo....",
        "oooooooooooooooooooooooooooooooooooooooooooooooooooo",
        "owwwwwwwwwwwwwwwwwwwwwmmmmmmmmwwwwwwwwwwwwwwwwwwwwwo",
        "osssssssssssssssssssssssssssssssssssssssssssssssssso",
        ".oooooooooooooooooooooooooooooooooooooooooooooooooo.",
    ]

    /// iPhone frame, 20×36. The screen is clear so each pose fills it.
    static let phoneArt: [String] = [
        "..oooooooooooooooo..",
        ".owwwwwwwwwwwwwwwwo.",
        "oskkkkkkkkkkkkkkkkso",
        "osk..............kso",
        "osk.....kkkk.....kso",
    ] + Array(repeating: "osk..............kso", count: 28) + [
        "oskkkkkkkkkkkkkkkkso",
        ".ommmmmmkkkkmmmmmmo.",
        "..oooooooooooooooo..",
    ]

    static let padlock: [String] = [
        "..sssss..",
        ".ss...ss.",
        ".s.....s.",
        ".s.....s.",
        "YYYYYYYYY",
        "YYYYYYYYY",
        "YYYYoYYYY",
        "YYYYoYYYY",
        "YYYYYYYYY",
    ]

    /// "Trust This Computer?" with Trust (F) and Don't Trust (B).
    static let trustAlert: [String] = [
        "PPPPPPPPPPPP",
        "PPwwwwwwwwPP",
        "PPPwwwwwwPPP",
        "PPPPPPPPPPPP",
        "PmmmmmmmmmmP",
        "PPmmmmmmmmPP",
        "PPPPPPPPPPPP",
        "FFFFFPBBBBBB",
        "FFFFFPBBBBBB",
    ]

    /// AirDrop waves, drawn smallest (1) to largest (3).
    static let arcs: [String] = [
        "........33....",
        "..........3...",
        "......22...3..",
        "........2...3.",
        "...11....2..3.",
        ".....1...2...3",
        "......1...2..3",
        "......1...2..3",
        "......1...2..3",
        ".....1...2...3",
        "...11....2..3.",
        "........2...3.",
        "......22...3..",
        "..........3...",
        "........33....",
    ]

    static func arcColors(_ t: Int?) -> [Character: Color] {
        let shown = t.map { [1, 2, 3, 3][$0 / 2 % 4] } ?? 3
        return Dictionary(uniqueKeysWithValues: ["1", "2", "3"].prefix(shown).map { ($0, Color.cofre.ink) })
    }

    static func mac(at x: Int, _ t: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            PixelArt(macArt, palette: palette)
            if (t ?? 0) % 4 < 2 { px(12, 17, 2, 1, .cofre.inkSoft) }
        }
        .at(x, 18)
    }

    /// Cable from the Mac's side along the ground and up into each phone's port. `gap` holds the plug short of the port;
    /// `flow` sends pixels toward the first phone.
    @ViewBuilder static func cable(macAt mx: Int, to ports: [Int], gap: Int = 0, flow: Int? = nil) -> some View {
        let exit = mx + 52, end = ports.max() ?? exit
        let line = Color.cofre.inkSoft
        px(exit, 49, 3, 1, line)
        px(exit + 2, 50, 1, 2, line)
        px(exit + 2, 52, end - exit - 1, 1, line)
        ForEach(ports, id: \.self) { c in
            px(c, 49 + gap, 1, 3 - gap, line)
            px(c - 1, 46 + gap, 3, 1, .cofre.muted)
            px(c - 1, 47 + gap, 3, 2, .cofre.ink)
        }
        if let flow, let port = ports.first {
            let path = (0..<3).map { (exit + $0, 49) } + (50...52).map { (exit + 2, $0) }
                + ((exit + 3)...port).map { ($0, 52) } + (49...51).reversed().map { (port, $0) }
            ForEach(Array(path.enumerated()), id: \.offset) { i, p in
                if (i - flow) % 4 == 0 { px(p.0, p.1, 1, 1, .cofre.accent) }
            }
        }
    }

    static func phone(at x: Int, _ screen: PhoneScreen, _ t: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            (screen == .off ? Color.cofre.well : Color.cofre.panel).frame(width: 14 * u, height: 30 * u).at(3, 3)
            screenContent(screen, t).frame(width: 14 * u, height: 30 * u).at(3, 3)
            PixelArt(phoneArt, palette: palette)
        }
        .at(x, 10)
    }

    @ViewBuilder static func screenContent(_ screen: PhoneScreen, _ t: Int?) -> some View {
        let blink = (t ?? 0) % 4 < 2
        switch screen {
        case .off: EmptyView()
        case .owner: PixelIcon(.head, size: 32)
        case .unlock:
            VStack(spacing: 0) {
                Color.cofre.ink.frame(width: 8 * u, height: 2 * u).padding(.top, 4 * u)
                Spacer()
                PixelArt(padlock, palette: palette)
                Spacer()
                Color.cofre.inkSoft.frame(width: 6 * u, height: u).opacity(blink ? 1 : 0.3).padding(.bottom, 2 * u)
            }
        case .trust:
            PixelArt(trustAlert, palette: palette.merging(["F": blink ? .cofre.faceBevel : .cofre.face]) { $1 })
        case .spinner: Spinner(size: 26)
        case .chest: PixelIcon(.chest, size: 40)
        case .done:
            VStack(spacing: 2 * u) { PixelIcon(.chest, size: 40); PixelIcon(.check, size: 28) }
        case .missing:
            AppIcon(size: 36).saturation(0).opacity(0.45)
                .padding(u)
                .overlay { Rectangle().strokeBorder(Color.cofre.muted, style: StrokeStyle(lineWidth: 2, dash: [4, 4])) }
        case .key: PixelIcon(.key, size: 40)
        case .cross: PixelIcon(.cross, size: 42)
        }
    }

    /// Twinkles around the phone when it's done: small pluses that swap places.
    @ViewBuilder static func sparkles(_ t: Int?) -> some View {
        let a = [(90, 12), (120, 24), (89, 36), (121, 5)], b = [(91, 25), (121, 14), (120, 38), (88, 4)]
        ForEach(Array(((t ?? 0) % 4 < 2 ? a : b).enumerated()), id: \.offset) { i, p in
            let c: Color = i % 2 == 0 ? .cofre.warn : .cofre.ink
            px(p.0 - 1, p.1, 3, 1, c)
            px(p.0, p.1 - 1, 1, 3, c)
        }
    }
}
