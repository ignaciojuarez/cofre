#if canImport(UIKit)
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
#endif
