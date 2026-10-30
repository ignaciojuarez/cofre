import CofreUI
import SwiftUI

// 8c. A loader install that fails while New instance is open: today the error goes to the page banner, hidden under
// the sheet. Here it shows in the sheet, above Create, with the one action that fixes it.
// The sheet's top half is rebuilt from public parts and scrolled to its end, where Create was just tapped.

enum LoaderErrorClean {
    struct Preview: View {
        let kind: String
        @Environment(\.horizontalSizeClass) private var sizeClass
        @State private var shown = false
        @State private var name = "Forge 1.20.1"

        var body: some View {
            PageBackground().ignoresSafeArea()
                .blockSheet(isPresented: Binding(get: { shown && sizeClass != .regular }, set: { shown = $0 })) { sheet }
                .overlay { if shown && sizeClass == .regular { ReviewCard(width: 540) { sheet } } }
                .task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    shown = true
                }
        }

        private var sheet: some View {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader("New instance")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ListSection("Name") { Field("Name", text: $name) }
                        ListSection("Version", spacing: 4) {
                            ValueRow("Version", value: "1.20.1", accent: true)
                            ValueRow("Forge", value: "47.3.0", accent: true)
                            Row("Java", trailing: { Meta("Auto") })
                        }
                        error
                        BlockButton("Create", role: .primary) {}
                    }
                    .padding(16)
                }
                .defaultScrollAnchor(.bottom)
            }
        }

        @ViewBuilder private var error: some View {
            if kind == "pairing" {
                Banner(DesignReview.loaderError(kind, clean: true), icon: .key, tone: .warn) {
                    BlockButton("Pair", size: .small) {}.fixedSize()
                }
            } else {
                Banner(DesignReview.loaderError(kind, clean: true), icon: .cross, tone: .danger) {
                    BlockButton("Close Cofre", size: .small) {}.fixedSize()
                }
                Note("Forge and NeoForge install once per launch.")
            }
        }
    }
}
