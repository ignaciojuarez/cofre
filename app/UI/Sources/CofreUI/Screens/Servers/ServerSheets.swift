#if canImport(UIKit)
    import SwiftUI

    /// Join on a server the active instance can't join: an instance that fits, a new one, or try anyway
    /// (plan/servers.md §Join).
    struct ServerVersionSheet: View {
        let choice: ServerVersionChoice
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader("Needs \(choice.needs)")
                VStack(alignment: .leading, spacing: 10) {
                    ServerRowFace(server: choice.server, ping: store.pingState(choice.server), instance: choice.current)
                    {
                        EmptyView()
                    }
                    Text(
                        "\(choice.current.name) runs \(choice.current.gameVersion), and \(choice.server.name) wants \(choice.needs). Join with an instance on that version."
                    )
                    .cofreFont(.secondary).foregroundStyle(Color.cofre.ink).fixedSize(horizontal: false, vertical: true)
                    if !choice.matches.isEmpty {
                        ListSection("Runs \(choice.needs)") {
                            ForEach(choice.matches) { i in
                                Row(i.name, subtitle: i.loaderLabel) {
                                    InstanceGlyph(icon: i.icon, size: 24)
                                } trailing: {
                                    BlockButton("Join", role: .primary, size: .small) { join(i) }
                                        .accessibilityLabel(Text("Join with \(i.name)"))
                                }
                            }
                        }
                    }
                    BlockButton(
                        "New \(choice.needs) instance", icon: .grass,
                        role: choice.matches.isEmpty ? .primary : .secondary
                    ) {
                        store.planInstance(for: choice)
                        nav.afterServerSheet = { nav.sheet = .newInstance }
                        dismiss()
                    }
                    VStack(spacing: 2) {
                        BlockButton("Try \(choice.current.name) anyway", role: .ghost) { join(choice.current) }
                        Text("Some servers let other versions in.").cofreFont(.caption)
                            .foregroundStyle(Color.cofre.muted)
                    }
                }
                .padding(16)
            }
        }

        private func join(_ i: InstanceSummary) {
            nav.afterServerSheet = {
                Task {
                    await store.join(choice.server, using: i.id)
                    nav.showingLaunch = true
                }
            }
            dismiss()
        }
    }
#endif
