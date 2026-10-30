import CofreUI
import SwiftUI

// 1 + 2. A plain `cofre://join?server=host:port` link: Cofre's sheet instead of system type and a pill button.
// The empty link opens the same sheet with the Join sheet's error look, instead of a banner over the page.

struct JoinServerClean: View {
    let server: String
    @Environment(CofreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var instanceID: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Join server")
            VStack(alignment: .leading, spacing: 10) {
                if server.isEmpty {
                    Banner("This link has no server address", icon: .cross, tone: .danger)
                    Note("Ask for a new link, or add the server in Play › Servers.")
                    BlockButton("Close") { dismiss() }
                } else if let instance = store.instances.first(where: { $0.id == instanceID }) ?? store.activeInstance {
                    ListSection(spacing: 4) {
                        Row(server, subtitle: "Saved to Servers", leading: { PixelIcon(.grass, size: 24) })
                        // Any instance can join; the menu only shows when there's a choice.
                        Menu {
                            Picker("Instance", selection: Binding(get: { instance.id }, set: { instanceID = $0 })) {
                                ForEach(store.instances) { Text(verbatim: $0.name).tag($0.id) }
                            }
                        } label: {
                            Row(instance.name, subtitle: instance.loaderLabel) {
                                InstanceGlyph(icon: instance.icon, size: 24)
                            } trailing: {
                                if store.instances.count > 1 { Meta("Change ▾") }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let error = store.lastError { Banner(error, icon: .cross, tone: .danger) }
                    BlockButton("Add and join", icon: .play, role: .primary, isLoading: saving) { saving = true }
                } else {
                    Banner("Make an instance first", icon: .grass, tone: .warn)
                    BlockButton("New instance", role: .primary) { dismiss() }
                }
            }
            .padding(16)
        }
    }

    struct Preview<Real: View>: View {
        let real: Real, server: String
        let nav: NavModel
        var body: some View {
            // Worlds behind it, like `-screen join`.
            real.reviewSheet(card: true) { JoinServerClean(server: server) }.task { nav.playPane = 1 }
        }
    }
}

/// Secondary note text under a banner, as the Join sheet's `NoteText`.
struct Note: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).cofreFont(.secondary).foregroundStyle(Color.cofre.muted).fixedSize(horizontal: false, vertical: true)
    }
}
