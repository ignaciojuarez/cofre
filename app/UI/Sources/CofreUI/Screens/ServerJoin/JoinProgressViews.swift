#if canImport(UIKit)
    import SwiftUI

    // Mockup 03 "Installing" and 04 "Server updated its pack".

    // MARK: - 03 Installing

    struct JoinInstallingBody: View {
        let state: ServerJoinInstallingState

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // XP bar: fills in segments with no tween, so it's the same under Reduce Motion.
                ProgressView(value: min(max(state.progressFraction, 0), 1)) { Text(verbatim: state.title) }
                    .progressViewStyle(.xp(.accent))
                    .accessibilityLabel(Text(verbatim: state.title))
                HStack(spacing: 8) {
                    Meta(state.formattedProgress)
                    Spacer(minLength: 8)
                    let rate = [
                        state.speedFormatted,
                        state.timeRemainingSeconds.map { String(localized: "\(joinDuration($0)) left") },
                    ]
                    .compactMap { $0 }.joined(separator: " · ")
                    if !rate.isEmpty { Meta(rate) }
                }
                .accessibilityElement(children: .combine)
            }
            // Pending steps keep full-contrast text (no dimming); the mark and "Next" say they're waiting.
            ListSection(spacing: 4) {
                ForEach(Array(state.stages.enumerated()), id: \.element.id) { i, stage in
                    Row(
                        stage.title, leading: { StatusMark(state: stage.state).frame(width: 14) },
                        trailing: {
                            Meta(meta(stage), tone: tone(stage, current: i == state.currentStageIndex))
                        }
                    )
                    .accessibilityValue(Text(meta(stage)))
                }
            }
            JoinNote {
                NoteText(
                    "You can close this. Keep Cofre open; if it closes, setup picks up where it stopped. Files are checked before use.",
                    color: Color.cofre.muted)
            }
            .accessibilityElement(children: .combine)
        }

        /// `.failed`'s text can be a raw error, so it never shows.
        private func meta(_ stage: InstallStage) -> String {
            switch stage.state {
            case .failed, .blocked: String(localized: "Failed")
            case .ready: stage.detail ?? String(localized: "Done")
            case .checking: stage.detail ?? String(localized: "Working")
            case .unknown: stage.detail ?? String(localized: "Next")
            }
        }

        private func tone(_ stage: InstallStage, current: Bool) -> Tone? {
            switch stage.state {
            case .failed, .blocked: .danger
            case .checking: current ? .neutral : nil
            default: nil
            }
        }
    }

    struct JoinInstallingFooter: View {
        let state: ServerJoinInstallingState
        let send: (ServerJoinAction) -> Void

        var body: some View {
            if state.canCancel {
                BlockButton("Cancel") { send(.cancelInstall) }.keyboardShortcut(".", modifiers: .command)
            }
        }
    }

    // MARK: - 04 Update available

    struct JoinUpdateBody: View {
        let update: ServerJoinUpdateState
        @Binding var showsAll: Bool
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        @Environment(\.openURL) var openURL

        private struct Change { let symbol: String, tone: Tone, name: String, meta: String, spoken: String }

        /// Added and removed first: they change how the game plays. Updates last.
        private var changes: [Change] {
            var out: [Change] = []
            for name in update.addedMods {
                out.append(
                    Change(
                        symbol: "+", tone: .success, name: name, meta: String(localized: "new"),
                        spoken: String(localized: "\(name), new")))
            }
            for name in update.removedMods {
                out.append(
                    Change(
                        symbol: "−", tone: .danger, name: name, meta: String(localized: "removed"),
                        spoken: String(localized: "\(name), removed")))
            }
            for m in update.updatedMods {
                out.append(
                    Change(
                        symbol: "↑", tone: .accent, name: m.name, meta: "\(m.fromVersion) → \(m.toVersion)",
                        spoken: String(localized: "\(m.name), \(m.fromVersion) to \(m.toVersion)")))
            }
            return out
        }
        private static let collapsedCount = 4

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips }
                VStack(alignment: .leading, spacing: 6) { chips }
            }
            .accessibilityElement(children: .combine)
            if update.isBreakingChange {
                JoinNote(tone: .warn) {
                    NoteText(
                        "Big update: Minecraft or the mod loader changes. Your current profile stays until this finishes."
                    )
                }
                .accessibilityElement(children: .combine)
            }
            let rows = showsAll ? changes : Array(changes.prefix(Self.collapsedCount))
            ListSection("What changed", spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, c in
                    Row(
                        c.name,
                        leading: {
                            Text(verbatim: c.symbol).cofreFont(.button).foregroundStyle(Color.cofre.tone(c.tone)).frame(
                                width: 16)
                        }, trailing: { Meta(c.meta) }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: c.spoken))
                }
                if !showsAll && changes.count > Self.collapsedCount {
                    let more = changes.count - Self.collapsedCount
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { showsAll = true }
                    } label: {
                        Row(
                            more == 1 ? String(localized: "1 more change") : String(localized: "\(more) more changes"),
                            leading: {
                                Text(verbatim: "…").cofreFont(.button).foregroundStyle(Color.cofre.muted).frame(
                                    width: 16)
                            })
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            if let url = update.changelogURL, url.scheme?.lowercased() == "https" {
                BlockButton("Release notes \(joinArrow)", role: .ghost, fullWidth: false) { openURL(url) }
            }
            NoteText(
                "Your worlds, settings and the optional mods you picked stay as they are.", color: Color.cofre.muted)
        }

        @ViewBuilder private var chips: some View {
            if !update.addedMods.isEmpty { Badge("+\(update.addedMods.count) new", tone: .success) }
            if !update.updatedMods.isEmpty { Badge("\(update.updatedMods.count) updated", tone: .accent) }
            if !update.removedMods.isEmpty { Badge("\(update.removedMods.count) removed", tone: .danger) }
            if let size = Fmt.bytes(update.downloadSizeBytes) { Badge(size) }
        }
    }

    struct JoinUpdateFooter: View {
        let update: ServerJoinUpdateState
        let send: (ServerJoinAction) -> Void

        var body: some View {
            VStack(spacing: 8) {
                JoinPrimaryButton(title: "Update & Join", size: Fmt.bytes(update.downloadSizeBytes)) { send(.update) }
                ToggleRow(
                    "Update this server automatically",
                    isOn: Binding(get: { update.autoUpdate }, set: { send(.setAutoUpdate($0)) }))
            }
        }
    }
#endif
