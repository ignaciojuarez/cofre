import SwiftUI

// Visual pieces of the in-game overlay: Cofre's square block in dark glass, pixel glyphs (plan/touch-controls.md).

enum OverlayGlyph {
    case jump, sneak, flyUp, flyDown, swimUp, swimDown, chat, pause, dots, moreVertical, menu, close, keyboard, dismount, eye,
        players, drop, swap, hide, edit

    init(_ g: TouchGlyph) {
        switch g {
        case .jump: self = .jump
        case .sneak: self = .sneak
        case .flyUp: self = .flyUp
        case .flyDown: self = .flyDown
        case .swimUp: self = .swimUp
        case .swimDown: self = .swimDown
        case .dismount: self = .dismount
        }
    }

    var rows: [String] {
        switch self {
        case .jump: ["...W...", "..WWW..", ".WWWWW.", "WWWWWWW", "..WWW..", "..WWW..", "..WWW.."]
        case .sneak: ["..WWW..", "..WWW..", "..WWW..", "WWWWWWW", ".WWWWW.", "..WWW..", "WWWWWWW"]
        case .flyUp: ["...W...", "..WWW..", ".WW.WW.", "WW...WW", "...W...", "..WWW..", ".WW.WW.", "WW...WW"]
        case .flyDown: ["WW...WW", ".WW.WW.", "..WWW..", "...W...", "WW...WW", ".WW.WW.", "..WWW..", "...W..."]
        case .swimUp: ["...W...", "..WWW..", ".WWWWW.", "..WWW..", ".......", "W.W.W.W", ".W.W.W."]
        case .swimDown: ["W.W.W.W", ".W.W.W.", ".......", "..WWW..", ".WWWWW.", "..WWW..", "...W..."]
        case .chat: ["WWWWWWW", "W.....W", "W.W.W.W", "W.....W", "WWWWWWW", ".WW....", ".W....."]
        case .pause: ["WW.WW", "WW.WW", "WW.WW", "WW.WW", "WW.WW", "WW.WW", "WW.WW"]
        case .dots: ["WW.WW.WW", "WW.WW.WW"]
        case .moreVertical: ["WW", "WW", "..", "WW", "WW", "..", "WW", "WW"]
        case .menu: ["WWWWWWW", ".......", "WWWWWWW", ".......", "WWWWWWW"]
        case .close: ["W.....W", ".W...W.", "..W.W..", "...W...", "..W.W..", ".W...W.", "W.....W"]
        case .keyboard: ["WWWWWWWWW", "W.W.W.W.W", "WWWWWWWWW", "W.W.W.W.W", "WWWWWWWWW", "W..WWW..W", "WWWWWWWWW"]
        case .dismount: ["WWWW...", "W......", "W..W...", "W..WW..", "W..WWWW", "W..WW..", "WWWWW.."]
        case .eye: [".WWWWW.", "W.....W", "W..W..W", "W.WWW.W", "W..W..W", "W.....W", ".WWWWW."]
        case .players: [".W...W.", "WWW.WWW", ".W...W.", ".......", "WWW.WWW", "WWW.WWW"]
        case .drop: ["..WWW..", "..WWW..", "WWWWWWW", ".WWWWW.", "..WWW..", "...W...", "WWWWWWW"]
        case .swap: ["..W....", ".WWWWWW", "..W...W", ".......", "W...W..", "WWWWWW.", "....W.."]
        case .hide: ["W.....W", ".WWWWW.", "W.W.W.W", "W.WWW.W", "W.W.W.W", ".WWWWW.", "W.....W"]
        case .edit: [".......", "....WW.", "...WWW.", "..WWW..", ".WWW...", "WW.....", "W......"]
        }
    }
}

/// Translucent square control: dark glass fill, light 2 pt outline, bevel and lip, pixel glyph. `on` uses the
/// accent face (locked sneak, open tray).
struct OverlayButton: View {
    let glyph: OverlayGlyph, size: CGFloat
    var on = false, pressed = false, flat = false
    var label: String?

    var body: some View {
        let px = max(2, (size * 0.5 / CGFloat(glyph.rows.first?.count ?? 7)).rounded(.down))
        ZStack {
            Rectangle().fill(
                on ? Color.cofre.face.opacity(0.9) : Color.black.opacity(pressed ? 0.6 : flat ? 0.55 : 0.4))
            if !flat {
                Color.white.opacity(0.14).frame(height: 2).padding([.horizontal, .top], 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                Color.black.opacity(0.35).frame(height: pressed ? 1 : 3).padding([.horizontal, .bottom], 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Rectangle().strokeBorder(Color.white.opacity(pressed ? 0.8 : flat ? 0.25 : 0.5), lineWidth: 2)
            PixelArt(glyph.rows, palette: ["W": Color.cofre.ink], pixel: px).offset(y: pressed ? 1 : 0)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            if let label {
                Text(verbatim: label).font(.cofre(.chip)).foregroundStyle(Color.cofre.ink).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.55))
                    .offset(y: 20)
            }
        }
    }
}

/// Square stick: a well with a beveled knob. Pushed to the top edge, the edge lights up and it sprints.
struct StickView: View {
    let size: CGFloat
    var knob: CGSize = .zero, sprinting = false, faint = false

    var body: some View {
        let knobSide = size * 0.41
        ZStack {
            Rectangle().fill(Color.black.opacity(faint ? 0.1 : 0.25))
            Rectangle().strokeBorder(Color.white.opacity(faint ? 0.22 : 0.4), lineWidth: 2)
            if sprinting {
                Color.cofre.accent.frame(height: 4).frame(maxHeight: .infinity, alignment: .top).padding(2)
                Text("SPRINT").font(.cofre(.label)).foregroundStyle(Color.cofre.accent).fixedSize()
                    .offset(y: -size / 2 - 12)
            }
            ZStack {
                Rectangle().fill(Color.white.opacity(0.3))
                Color.white.opacity(0.3).frame(height: 2).padding([.horizontal, .top], 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
            }
            .frame(width: knobSide, height: knobSide)
            .offset(knob)
        }
        .frame(width: size, height: size)
    }
}

enum TrayItem: CaseIterable {
    case pause, chat, inventory, view, players, drop, swap, hideHUD, keyboard

    var glyph: OverlayGlyph {
        switch self {
        case .pause: .pause
        case .chat: .chat
        case .inventory: .dots
        case .view: .eye
        case .players: .players
        case .drop: .drop
        case .swap: .swap
        case .hideHUD: .hide
        case .keyboard: .keyboard
        }
    }

    var title: String {
        switch self {
        case .pause: String(localized: "Pause")
        case .chat: String(localized: "Chat")
        case .inventory: String(localized: "Inventory")
        case .view: String(localized: "View")
        case .players: String(localized: "Players")
        case .drop: String(localized: "Drop")
        case .swap: String(localized: "Swap hands")
        case .hideHUD: String(localized: "Hide HUD")
        case .keyboard: String(localized: "Keyboard")
        }
    }

    /// Dock and Classic already show pause, chat and inventory; Minimal's ≡ tray carries them.
    static func items(for style: TouchLayoutStyle) -> [TrayItem] {
        let extras: [TrayItem] = [.view, .players, .drop, .swap, .hideHUD, .keyboard]
        return style == .minimal ? [.pause, .chat, .inventory] + extras : extras
    }
}

/// Quick tray: a grid of rarer actions under the ⋮ (or ≡) button, starting with Pause.
struct QuickTray: View {
    let items: [QuickTrayAction?], k: CGFloat
    var on: Set<QuickTrayActionID> = []
    let down: (QuickTrayAction) -> Void
    let up: (QuickTrayAction) -> Void
    let edit: () -> Void

    private var cells: [QuickTrayAction] {
        let pause = QuickTrayAction(id: .pause, label: "Pause", keys: [.escape])
        let editAction = QuickTrayAction(id: .edit, label: "Edit", keys: [])
        let slots = items.enumerated().map { pair in
            pair.element ?? QuickTrayAction(id: .emptySlot(pair.offset), label: "", keys: [])
        }
        return [pause] + slots + [editAction]
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { c in
                        QuickTrayTile(
                            item: cells[(r * 4) + c], k: k, on: on,
                            down: down, up: up, edit: edit)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .overlay { Rectangle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2) }
    }

}

private struct QuickTrayTile: View {
    let item: QuickTrayAction, k: CGFloat, on: Set<QuickTrayActionID>
    let down: (QuickTrayAction) -> Void, up: (QuickTrayAction) -> Void, edit: () -> Void
    @State private var active = false

    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !item.id.isEmptySlot else { return }
                guard !active else { return }
                active = true
                if item.id != .edit { down(item) }
            }
            .onEnded { _ in
                guard !item.id.isEmptySlot else { return }
                if item.id == .edit { edit() } else { up(item) }
                active = false
            }
        return VStack(spacing: 3) {
            OverlayButton(
                glyph: item.id == .edit ? .edit : item.glyph,
                size: 40 * k, on: on.contains(item.id) || item.id == .pause || item.id == .edit)
            Text(verbatim: item.label).font(.cofre(.label)).foregroundStyle(Color.cofre.ink).fixedSize()
        }
        .frame(width: 64 * k)
        .contentShape(Rectangle())
        .opacity(item.id.isEmptySlot ? 0.4 : 1)
        .accessibilityLabel(Text(verbatim: item.label))
        .gesture(gesture)
    }
}
