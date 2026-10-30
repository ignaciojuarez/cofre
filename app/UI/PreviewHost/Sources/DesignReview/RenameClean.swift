import CofreUI
import SwiftUI

// 3. Instance ⋯ → Rename…: the menu names what it does, and Save waits for a new, non-empty name.

enum RenameClean {
    struct Preview<Real: View>: View {
        let real: Real
        let nav: NavModel, store: CofreStore
        @State private var shown = false
        @State private var name = ""

        var body: some View {
            let current = store.instances.first { $0.id == "survival" }?.name ?? ""
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            real
                .alert("Rename", isPresented: $shown) {
                    TextField("Name", text: $name).submitLabel(.done)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") {}.disabled(trimmed.isEmpty || trimmed == current)
                }
                .task {
                    nav.section = .instances
                    nav.instance = "survival"
                    while !store.libraryLoaded { try? await Task.sleep(for: .milliseconds(100)) }
                    try? await Task.sleep(for: .milliseconds(1500))
                    name = store.instances.first { $0.id == "survival" }?.name ?? ""
                    shown = true
                }
        }
    }
}
