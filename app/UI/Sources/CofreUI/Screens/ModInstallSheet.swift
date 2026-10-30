#if canImport(UIKit)
    import SwiftUI

    // M05 Get sheet: a short hugging sheet. It opens only when Get does more than install the one project (extra
    // required mods, optional ones, a modpack), or when it can't. One sheet walks through confirm → progress → done or
    // failed; closing it mid-install keeps going on the row.

    /// `store.modInstallSheet` as a sheet item.
    struct ModInstallRoute: Identifiable, Hashable {
        let id: String
    }

    struct ModInstallSheet: View {
        let id: String
        @Environment(CofreStore.self) private var store
        @Environment(\.dismiss) private var dismiss
        /// Long dependency lists fold after this many rows, so the sheet still hugs.
        private let shown = 5

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let job = store.modInstalls[id] {
                    SheetHeader(job.phase == .done ? "\(job.title)" : "Get \(job.title)")
                    VStack(alignment: .leading, spacing: 10) { content(job) }
                        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
                }
            }
        }

        @ViewBuilder private func content(_ job: ModInstall) -> some View {
            switch job.phase {
            case .planning:
                Row("Checking what it needs…", leading: { Spinner() })
            case .confirm:
                if let plan = job.plan { confirm(job, plan) }
            case .queued, .installing:
                progress(job)
                if job.phase == .queued {
                    Text("Waiting for the other install to finish.").cofreFont(.secondary)
                        .foregroundStyle(Color.cofre.muted)
                }
                BlockButton("Hide · keeps going") { dismiss() }
            case .done:
                Banner(doneTitle(job), icon: .check, tone: .success)
                progress(job)
                BlockButton("Done", role: .primary) { dismiss() }
            case .failed(let reason):
                Banner(String(localized: "Couldn't install \(job.title)"), icon: .cross, tone: .danger)
                Text(verbatim: reason).cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing was installed.").cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                if job.progress?.stages.contains(where: { $0.state.isFailed }) == true { stages(job) }
                if job.canRetry {
                    BlockButton("Try again", role: .primary) { store.retryInstall(id) }
                }
                BlockButton("Close") { dismiss() }
            }
        }

        // MARK: Confirm

        @ViewBuilder private func confirm(_ job: ModInstall, _ plan: ModInstallPlan) -> some View {
            let target = store.instances.first { $0.id == job.instanceID }
            let issue = target.flatMap {
                ModCompatibility.entry(for: plan.target.id, name: plan.target.name)?.issue(
                    gameVersion: $0.gameVersion,
                    renderer: ModCompatibility.renderer(
                        setting: store.preferences.renderer, gameVersion: $0.gameVersion, loader: $0.loader.rawValue))
            }
            // The warning leads, in one line.
            if let issue {
                Banner("Won't run on \(issue.gameVersion) with Metal", icon: .ore, tone: .warn)
                Text(verbatim: issue.reason).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Row(
                plan.target.name,
                subtitle: plan.makesInstance
                    ? String(localized: "New instance")
                    : [plan.target.version, target.map { "\($0.name) · \($0.loaderLabel)" }]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            ) {
                icon(plan.target.id)
            } trailing: {
                HStack(spacing: 6) {
                    channelBadge(plan.target)
                    Meta(Fmt.fileSize(plan.target.sizeBytes) ?? "")
                }
            }
            if plan.target.channel != .release {
                Text("No release fits \(target?.name ?? "this instance") yet, so this is the newest \(plan.target.channel.label.lowercased()).")
                    .cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.makesInstance {
                Text("Packs make their own instance, so \(target?.name ?? "your instance") stays as it is.")
                    .cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !plan.required.isEmpty {
                SectionLabel("Also installs · needed to run")
                ListSection(spacing: 4) {
                    ForEach(plan.required.prefix(plan.required.count > shown ? shown - 1 : shown)) { m in
                        Row(m.name, leading: { icon(m.id) }) {
                            if m.turnsOn {
                                Meta("Turns on", tone: .warn)
                            } else {
                                HStack(spacing: 6) {
                                    channelBadge(m)
                                    Meta(Fmt.fileSize(m.sizeBytes) ?? "")
                                }
                            }
                        }
                    }
                    if plan.required.count > shown {
                        Row(
                            "\(plan.required.count - shown + 1) more",
                            subtitle: plan.required.dropFirst(shown - 1).map(\.name).joined(separator: ", "))
                    }
                }
            }
            if !plan.optional.isEmpty {
                SectionLabel("Optional")
                ListSection(spacing: 4) {
                    ForEach(plan.optional) { m in
                        ToggleRow(m.name, subtitle: Fmt.fileSize(m.sizeBytes), isOn: picked(m.id))
                    }
                }
            }
            if !plan.present.isEmpty {
                Text("Already has \(ListFormatter.localizedString(byJoining: plan.present)).")
                    .cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
            }
            // Secondary when it won't run, so the risky path doesn't look recommended.
            BlockButton(
                issue == nil ? installTitle(job, plan) : String(localized: "Install anyway · \(Fmt.fileSize(job.downloadBytes) ?? "")"),
                role: issue == nil ? .primary : .secondary
            ) { store.confirmInstall(id) }
                .keyboardShortcut(.return, modifiers: .command)
        }

        private func installTitle(_ job: ModInstall, _ plan: ModInstallPlan) -> String {
            let count = plan.files(picking: job.picked).count
            let verb =
                plan.makesInstance
                ? String(localized: "Install pack")
                : count > 1 ? String(localized: "Install \(count)") : String(localized: "Install")
            return [verb, Fmt.fileSize(job.downloadBytes)].compactMap { $0 }.joined(separator: " · ")
        }

        private func picked(_ optionalID: String) -> Binding<Bool> {
            Binding(
                get: { store.modInstalls[id]?.picked.contains(optionalID) == true },
                set: { on in
                    if on {
                        store.modInstalls[id]?.picked.insert(optionalID)
                    } else {
                        store.modInstalls[id]?.picked.remove(optionalID)
                    }
                })
        }

        // MARK: Progress

        @ViewBuilder private func progress(_ job: ModInstall) -> some View {
            if let p = job.progress {
                if job.phase != .done {
                    ProgressView(value: p.fraction).progressViewStyle(.xp())
                        .accessibilityLabel(Text("Installing"))
                }
                stages(job)
            }
        }

        private func stages(_ job: ModInstall) -> some View {
            let all = job.progress?.stages ?? []
            // Long lists keep the running and failed ones in view.
            let visible =
                all.count > shown ? Array(all.filter { $0.state != .ready && $0.state != .unknown }.prefix(shown - 1)) : all
            return ListSection(spacing: 4) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, s in
                    Row(s.title, leading: { StatusMark(state: s.state).frame(width: 14) }) {
                        Meta(
                            s.state.isReady ? "OK" : s.state.isFailed ? String(localized: "Failed") : (s.detail ?? ""),
                            tone: s.state.isReady ? .success : s.state.isFailed ? .danger : nil)
                    }
                    .dimmed(s.state == .unknown)
                }
                if all.count > shown {
                    let done = all.filter(\.state.isReady).count
                    Row("\(done) of \(all.count) ready", leading: { PixelIcon(.chest, size: 14) })
                }
            }
        }

        private func doneTitle(_ job: ModInstall) -> String {
            if job.plan?.makesInstance == true { return String(localized: "Made a new instance") }
            let name = store.instances.first { $0.id == job.instanceID }?.name ?? ""
            return String(localized: "Installed in \(name)")
        }

        @ViewBuilder private func channelBadge(_ m: PlannedMod) -> some View {
            if m.channel != .release {
                Badge(m.channel.label, tone: m.channel == .beta ? .warn : .danger)
            }
        }

        /// The project's icon when it's in the results, else a book.
        @ViewBuilder private func icon(_ projectID: String) -> some View {
            if let p = store.results.first(where: { $0.id == projectID }) {
                ProjectIcon(project: p, size: 24)
            } else {
                PixelIcon(.book, size: 18).frame(width: 24, height: 24)
            }
        }
    }
#endif

#if canImport(UIKit)
    extension Fmt {
        /// Mod-sized files: "386 KB", "2.4 MB".
        static func fileSize(_ b: Int64?) -> String? {
            b.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        }
    }
#endif
