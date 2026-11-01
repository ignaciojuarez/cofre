#if canImport(UIKit)
    import CofreKit
    import SwiftUI

    /// The Play-time check: what won't run with this instance's renderer, before the game starts. "Turn off and
    /// play" turns off the flagged mods, and shaders through the shader mod's own switch.
    struct PlayCheckRoute: Identifiable {
        let issues: [ModCompatibilityIssue]
        var id: Int { issues.hashValue }
    }

    struct PlayCompatibilitySheet: View {
        let issues: [ModCompatibilityIssue]
        /// Play started: the root shows the launch once this sheet has closed.
        let launch: () -> Void
        @Environment(CofreStore.self) private var store

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    LocalizedStringKey(
                        issues.count == 1 ? issues[0].title : String(localized: "\(issues.count) things don't run here")
                    ))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(issues, id: \.self) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(
                                    verbatim: issue.kind == .shaders
                                        ? String(localized: "Shaders · \(issue.modName)") : issue.modName
                                )
                                .cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                                Spacer(minLength: 4)
                                Badge(issue.badge, tone: .warn)
                            }
                            Text(verbatim: issue.reason).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 8).block(.panel)
                    }
                    BlockButton("Turn off and play", role: .primary) { play(turnOff: true) }
                        .keyboardShortcut(.return, modifiers: .command)
                    BlockButton("Play anyway") { play(turnOff: false) }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            }
        }

        private func play(turnOff: Bool) {
            launch()
            store.playAnywayAfterModWarning(turnOff: turnOff)
        }
    }

    /// Play's other check, over the launch screen: a Forge/NeoForge mod needs a library that isn't installed, which
    /// would stop the game before its first frame. "Get and play" installs them, then launches.
    struct PlayRequirementsRoute: Identifiable {
        let missing: [ModRequirement]
        var id: Int { missing.hashValue }

        /// "Biomes O' Plenty needs TerraBlender, GlitchCore", one line per needing mod, in order.
        var lines: [String] {
            var order: [String] = []
            var needs: [String: [String]] = [:]
            for r in missing {
                let by = r.neededBy ?? String(localized: "A mod")
                if needs[by] == nil { order.append(by) }
                needs[by, default: []].append(r.name)
            }
            return order.map { String(localized: "\($0) needs \(needs[$0]!.formatted())") }
        }
    }

    struct PlayRequirementsSheet: View {
        let route: PlayRequirementsRoute
        @Environment(CofreStore.self) private var store

        var body: some View {
            let lines = route.lines
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    LocalizedStringKey(lines.count == 1 ? lines[0] : String(localized: "Some mods need others")))
                VStack(alignment: .leading, spacing: 10) {
                    if lines.count > 1 {
                        ForEach(lines, id: \.self) { line in
                            Text(verbatim: line).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading).block(.panel)
                        }
                    }
                    Text("Without them, Minecraft stops before it starts.").cofreFont(.secondary)
                        .foregroundStyle(Color.cofre.muted).fixedSize(horizontal: false, vertical: true)
                    BlockButton("Get and play", icon: .chest, role: .primary) {
                        store.resolvePlayRequirements(get: true)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    BlockButton("Play anyway") { store.resolvePlayRequirements(get: false) }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            }
        }
    }
#endif
