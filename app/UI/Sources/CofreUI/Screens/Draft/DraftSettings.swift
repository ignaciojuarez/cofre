#if canImport(UIKit)
    import SwiftUI

    // Draft · Settings additions. Logs (live tail of the game's own latest.log with search and filter), the share
    // report sheet (one zip, personal details hidden first; the crash screen's Share opens it too) and the small
    // account states (expired, demo, remove). Logs: live · errors · share. Accounts: list · remove.

    struct LogsDraft: View {
        let state: String
        @State private var kind = LogKind.latest
        @State private var search = ""
        @State private var level = "all"

        var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Logs") { Badge("Live", tone: .success) }
                    .environment(\.isPushed, true)
                DraftScroll {
                    Segmented(
                        "Log", selection: $kind, options: [(.latest, "Game"), (.crash, "Crash"), (.launcher, "Cofre")])
                    Field("Search log", text: $search, kind: .search, trailingNote: search.isEmpty ? nil : "2 found")
                    ChipGroup(
                        "Show", selection: $level,
                        options: [
                            ("all", "All"), ("problems", "Warnings · 3"), ("errors", "Errors · 1"), ("mods", "Mods"),
                        ])
                    LogView(lines: shown, follow: false).frame(height: state == "errors" ? 150 : 330)
                    HStack(spacing: 8) {
                        BlockButton("Pause", fullWidth: false) {}
                        BlockButton("Share report…", icon: .paper, role: .primary) {}
                    }
                    GameOwnsNote(
                        "Reads latest.log as the game writes it. Nothing leaves this iPhone unless you share it.")
                }
            }
            .onAppear {
                if state == "errors" {
                    level = "problems"
                    search = "shader"
                }
            }
            .draftSheet(state == "share") { ShareReportSheet() }
        }

        private var shown: [LogLine] {
            let all = Self.lines
            guard state == "errors" else { return all }
            return all.filter { $0.level == .warning || $0.level == .error }.filter {
                $0.text.localizedCaseInsensitiveContains(search) || search.isEmpty
            }
        }

        static let lines: [LogLine] = [
            .init(id: 0, time: "14:02:11", tag: "main", text: "Loading Minecraft 1.21.1 with Fabric Loader 0.16.14"),
            .init(id: 1, time: "14:02:12", tag: "main", text: "Loading 142 mods"),
            .init(
                id: 2, time: "14:02:15", tag: "main", text: "Better Glass needs Fabric API, which isn't installed",
                level: .warning),
            .init(id: 3, time: "14:02:18", tag: "Render", text: "Backend library: LWJGL version 3.3.3"),
            .init(id: 4, time: "14:02:19", tag: "Render", text: "Renderer: MobileGlues 1.3 (OpenGL 4.0 on Metal)"),
            .init(id: 5, time: "14:02:21", tag: "Sodium", text: "Using the optimized chunk renderer"),
            .init(id: 6, time: "14:02:24", tag: "Iris", text: "Shader compile took 1,840 ms", level: .warning),
            .init(id: 7, time: "14:02:30", tag: "Server", text: "Preparing level \"Ironwood\""),
            .init(
                id: 8, time: "14:02:34", tag: "Iris",
                text: "Shader pack \"Sildur's Vibrant\" needs a missing GL feature", level: .error),
            .init(id: 9, time: "14:02:35", tag: "Server", text: "Done (4.9 s)!", level: .success),
            .init(id: 10, time: "14:02:36", tag: "Render", text: "Setting user: Steve_42"),
            .init(id: 11, time: "14:02:41", tag: "Cofre", text: "Thermal state fair · Balanced kept"),
            .init(id: 12, time: "14:03:02", tag: "Server", text: "Saving chunks for level 'Ironwood'", level: .warning),
        ]
    }

    /// One zip: the logs, the crash report, the mod list and device facts. Personal details are hidden before it
    /// leaves; the preview shows how.
    struct ShareReportSheet: View {
        var crash = false
        @State private var game = true
        @State private var crashReport = true
        @State private var cofre = true
        @State private var mods = true
        @State private var device = true

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Share report")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Hidden before it leaves")
                            Text(
                                "Your username, account ID, sign-in tokens, server addresses and your name in file paths."
                            )
                            .cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            Text(
                                verbatim: """
                                    14:02:36 [Render] Setting user: ‹player›
                                    14:02:41 [Client] Connecting to ‹server›
                                    14:02:41 [Auth] Session ‹token hidden›
                                    """
                            )
                            .cofreFont(.code).foregroundStyle(Color.cofre.inkSoft)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading).block(.well)
                        }
                        ListSection("Include", spacing: 4) {
                            ToggleRow("Game log", subtitle: "latest.log · 214 KB", isOn: $game)
                            ToggleRow("Crash report", subtitle: "crash-2026-10-29_14.02.40.txt", isOn: $crashReport)
                            ToggleRow("Cofre log", subtitle: "Launch steps, JIT, memory", isOn: $cofre)
                            ToggleRow("Mod list", subtitle: "142 mods with versions", isOn: $mods)
                            ToggleRow(
                                "Device and settings", subtitle: "iPhone 17 Pro · iOS 26.1 · Balanced · Metal",
                                isOn: $device)
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 8) {
                    BlockButton("Copy summary") {}
                    BlockButton("Share · 238 KB", icon: .paper, role: .primary) {}
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    /// The real crash screen with its Share button opening the report sheet.
    struct CrashShareDraft: View {
        var body: some View {
            GameExitView(report: MockGameExit.report(.renderer), close: {})
                .draftSheet(true) { ShareReportSheet(crash: true) }
        }
    }

    // MARK: Accounts (small)

    struct AccountsDraft: View {
        let state: String
        @State private var removing = false

        var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Accounts & data").environment(\.isPushed, true)
                DraftScroll {
                    ListSection(spacing: 4) {
                        Row("Steve_42", subtitle: "Microsoft · plays as this", leading: { PixelIcon(.head, size: 26) })
                        {
                            Badge("Active", tone: .success)
                        }
                        Row("Alex_Mines") {
                            Text("Signed out · sign in again").cofreFont(.caption).foregroundStyle(Color.cofre.danger)
                        } leading: {
                            PixelIcon(.head, size: 26).opacity(0.55)
                        } trailing: {
                            BlockButton("Sign in", role: .primary, size: .small) {}
                        }
                        Row("DemoKid") {
                            Text("Doesn't own Java Edition · demo only").cofreFont(.caption).foregroundStyle(
                                Color.cofre.warn)
                        } leading: {
                            PixelIcon(.head, size: 26)
                        } trailing: {
                            Badge("Demo", tone: .warn)
                        }
                        BlockButton("Add account", icon: .head) {}
                    }
                    GameOwnsNote(
                        "Remove an account by swiping it or holding it. Worlds and instances stay on this iPhone.")
                }
            }
            .alert("Remove Alex_Mines?", isPresented: $removing) {
                Button("Remove", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can sign in again any time. Worlds and instances stay on this iPhone.")
            }
            .task {
                guard state == "remove" else { return }
                try? await Task.sleep(for: .milliseconds(300))
                removing = true
            }
        }
    }
#endif
