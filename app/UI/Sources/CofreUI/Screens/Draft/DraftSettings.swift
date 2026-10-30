#if canImport(UIKit)
    import SwiftUI

    // Draft · Settings additions. Logs (live tail of the game's own latest.log with search and filter), the share
    // report sheet (one zip, personal details hidden first; the crash screen's Share opens it too) and the small
    // account states (expired, demo, remove). Logs: live · errors · share. Accounts: list · remove.

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
