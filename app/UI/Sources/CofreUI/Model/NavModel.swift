#if canImport(UIKit)
import SwiftUI

// §3.3: one nav model per window. All navigation state lives here, not in view identity,
// so resizing between compact and regular keeps the selection (W1 → I1).

public enum SettingsPane: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case game, renderer, touch, controller, controlsEditor, jitJava, accounts, logs, look, about
    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .game: "Game"; case .renderer: "Renderer"; case .touch: "Touch & gyro"; case .controller: "Controller"
        case .controlsEditor: "Controls editor"; case .jitJava: "JIT & Java"; case .accounts: "Accounts & data"
        case .logs: "Logs"; case .look: "Look & more"; case .about: "About"
        }
    }
    var glyph: PixelGlyph {
        switch self {
        case .game: .grass; case .renderer: .ore; case .touch, .controller, .controlsEditor: .cmd
        case .jitJava: .bolt; case .accounts: .head; case .logs: .paper; case .look: .book; case .about: .shield
        }
    }
    static let groups: [(LocalizedStringKey, [SettingsPane])] = [
        ("Game", [.game, .renderer]), ("Controls", [.touch, .controller, .controlsEditor]),
        ("System", [.jitJava, .accounts, .logs, .look, .about]),
    ]
}

/// Mods detail column: a project page or the installed manager.
public enum ModsRoute: Hashable, Codable, Sendable {
    case installed
    case project(String)
}

public enum ActiveSheet: String, Identifiable, Sendable { case newInstance, importPack
    public var id: String { rawValue }
}

@Observable @MainActor
public final class NavModel {
    public enum Section: String, CaseIterable, Codable, Sendable {
        case play, instances, mods, settings
        var title: LocalizedStringKey {
            switch self { case .play: "Play"; case .instances: "Instances"; case .mods: "Mods"; case .settings: "Settings" }
        }
        var glyph: PixelGlyph {
            switch self { case .play: .play; case .instances: .grass; case .mods: .book; case .settings: .gear }
        }
        var shortcut: KeyEquivalent {
            switch self { case .play: "1"; case .instances: "2"; case .mods: "3"; case .settings: "4" }
        }
    }

    public var section: Section = .play
    /// Instance detail selection (Instances section).
    public var instance: String?
    public var mod: ModsRoute?
    public var settingsPane: SettingsPane?
    /// Play's compact segmented fallback: 0 = Play, 1 = Worlds.
    public var playPane = 0
    public var sheet: ActiveSheet?
    /// ⌃⌘S: regular width shows the rail even when the sidebar would fit.
    public var preferRail = false
    public var showingLaunch = false
    public var showingAirScreen: AirScreenRoute?
    /// The Join server sheet (GAP-14). Shown only when the backend reports `.serverJoin`, and after setup.
    public var serverJoin: ServerJoinRequest?

    public init() {}

    /// Routes a deep link. `cofre://join?server=…&card=…&pin=…` opens the Join server sheet. The shell forwards
    /// `scene(_:openURLContexts:)` here; returns `false` for links Cofre doesn't handle.
    @discardableResult public func open(_ url: URL) -> Bool {
        guard let request = ServerJoinRequest(url: url) else { return false }
        serverJoin = request
        return true
    }

    // §3.3: section and selection are saved per scene in `stateRestorationActivity`.
    public struct Snapshot: Codable, Sendable {
        public var section: Section, instance: String?, mod: ModsRoute?, settingsPane: SettingsPane?
    }
    public var snapshot: Snapshot {
        get { Snapshot(section: section, instance: instance, mod: mod, settingsPane: settingsPane) }
        set { section = newValue.section; instance = newValue.instance; mod = newValue.mod; settingsPane = newValue.settingsPane }
    }
    public static let activityType = "app.cofre.nav"
    public func userActivity() -> NSUserActivity {
        let a = NSUserActivity(activityType: Self.activityType)
        if let data = try? JSONEncoder().encode(snapshot) { a.addUserInfoEntries(from: ["nav": data]) }
        return a
    }
    public func restore(from activity: NSUserActivity?) {
        guard let data = activity?.userInfo?["nav"] as? Data, let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = s
    }
}

public enum AirScreenRoute: Identifiable, Hashable, Sendable {
    case controlsEditor, forgeInstaller(String)
    public var id: String { switch self { case .controlsEditor: "controls"; case .forgeInstaller(let i): "forge-\(i)" } }
}
#endif
