import CofreUI
import SwiftUI

// 4. Get a mod that won't run with Metal: the warning leads, says why in one line, and the button keeps the sheet's
// own verb and size. It's secondary, so the risky path doesn't look recommended.

struct ModWarningClean: View {
    let job: ModInstall, plan: ModInstallPlan, instance: InstanceSummary
    @Environment(CofreStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Get \(plan.target.name)")
            VStack(alignment: .leading, spacing: 10) {
                Banner("Won't run on \(instance.gameVersion) with Metal", icon: .ore, tone: .warn)
                Note(LocalizedStringKey(Self.reason(plan.target.name)))
                ListSection(spacing: 4) {
                    Row(plan.target.name, subtitle: "\(plan.target.version) · \(instance.name) · \(instance.loaderLabel)") {
                        icon(plan.target.id)
                    } trailing: {
                        Meta(Self.size(plan.target.sizeBytes))
                    }
                    ForEach(plan.required) { m in
                        Row(m.name, subtitle: "Needed to run") {
                            icon(m.id)
                        } trailing: {
                            Meta(Self.size(m.sizeBytes))
                        }
                    }
                }
                if !plan.present.isEmpty {
                    Note("Already has \(ListFormatter.localizedString(byJoining: plan.present)).")
                }
                BlockButton("Install anyway · \(Self.size(job.downloadBytes))") {}
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
        }
    }

    /// The project's icon from the results, as the real sheet's `icon(_:)`.
    private func icon(_ id: String) -> some View {
        AsyncImage(url: store.results.first { $0.id == id }?.iconURL) { $0.interpolation(.none).resizable() } placeholder: {
            PixelIcon(.book, size: 18)
        }
        .frame(width: 24, height: 24)
    }

    /// Proposed `ModCompatibility` reasons: one plain sentence, no "integration" or "manifest".
    static func reason(_ name: String) -> String {
        let key = name.lowercased()
        if key.contains("iris") { return "Metal runs Iris on Minecraft 26.2 only." }
        if key.contains("sodium") { return "Metal runs Sodium on Minecraft 26.2 and 1.21.11 only." }
        return "Cofre's Metal renderer can't run it yet."
    }

    static func size(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
    }

    struct Preview<Real: View>: View {
        let real: Real
        let nav: NavModel
        @Environment(CofreStore.self) private var store
        @State private var ready = false

        var body: some View {
            real.reviewSheet(when: ready) {
                if let job = store.modInstalls["iris"], let plan = job.plan, let inst = store.modsInstance {
                    ModWarningClean(job: job, plan: plan, instance: inst)
                }
            }
            .task {
                nav.section = .mods
                while store.results.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                store.get("iris")
                // Today's sheet stays closed; this one shows the same plan.
                while store.modInstalls["iris"]?.phase != .confirm { try? await Task.sleep(for: .milliseconds(20)) }
                store.modInstallSheet = nil
                ready = true
            }
        }
    }
}
