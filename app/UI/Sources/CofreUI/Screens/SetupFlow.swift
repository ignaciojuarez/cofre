#if canImport(UIKit)
    import SwiftUI

    // S01–S08. Six checks, one per `SetupState` field. Each step checks itself and moves on when it passes:
    // Developer Mode, key found, VPN allowed and JIT OK advance on their own, and the JIT test starts by itself.
    // The step is saved, so a cold start resumes there. CenteredCard: full screen on compact, a 560 pt card on regular.

    public struct SetupFlow: View {
        @Environment(CofreStore.self) private var store
        @State private var step: Int
        private let startAt: Int?

        static let stepNames: [LocalizedStringKey] = ["Dev Mode", "Trust", "Pairing", "VPN", "JIT", "Account"]

        /// `startAt`: 0 = welcome, 1…6 = checks, 7 = ready. `nil` uses `CofreStore.resumeStep`.
        public init(startAt: Int? = nil) {
            self.startAt = startAt
            _step = State(initialValue: startAt ?? 0)
        }

        public var body: some View {
            CenteredCard {
                Group {
                    switch step {
                    case 0: WelcomeStep(next: { step = store.firstOpenStep })
                    case 1: DevModeStep(step: $step, next: next)
                    case 2: TrustStep(step: $step, next: next)
                    case 3: PairingStep(step: $step, next: next)
                    case 4: VPNStep(step: $step, next: next)
                    case 5: JITTestStep(step: $step, next: next)
                    case 6: AccountStep(step: $step, next: next)
                    default: ReadyStep()
                    }
                }
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.15), value: step)
            .onAppear { if startAt == nil { step = store.resumeStep } }
            .onChange(of: step, initial: true) { store.setupStep = step }
            .onChange(of: store.setup) { old, new in
                // Auto-advance when the current step's check turns ready, after a beat so the check is seen.
                let from = step
                guard (1...6).contains(from), !old.all[from - 1].isReady, new.all[from - 1].isReady else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    if step == from { next() }
                }
            }
        }

        /// The next check that isn't ready, after this one. Steps run in order; none can be skipped.
        private func next() {
            step = (step..<6).first { !store.setup.all[$0].isReady }.map { $0 + 1 } ?? 7
        }
    }

    /// Header shared by S02–S07: back, counter, StepBar, icon, title, lede.
    private struct StepHeader: View {
        let index: Int, glyph: PixelGlyph, title: LocalizedStringKey,
            lede: LocalizedStringKey?
        @Binding var step: Int
        @Environment(\.widthClass) private var width

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        step -= 1
                    } label: {
                        Text(verbatim: "‹").cofreFont(.header).foregroundStyle(Color.cofre.accent).frame(
                            minWidth: 44, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain).keyboardShortcut(.escape, modifiers: []).accessibilityLabel(Text("Back"))
                    Spacer()
                    Meta("\(index)/6")
                }
                .padding(.vertical, -8)
                StepBar(steps: SetupFlow.stepNames, current: index - 1)
                PixelIcon(glyph, size: 44).padding(.top, 6)
                Text(title).cofreFont(.title).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
                if let lede { Text(lede).cofreFont(.secondary).foregroundStyle(Color.cofre.muted) }
            }
        }
    }

    // MARK: S01 Welcome

    private struct WelcomeStep: View {
        let next: () -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                PixelScene(seed: 11, pixels: .init(width: 240, height: 84))
                    // The scene's ideal width (428 pt at this height) must not widen the card on small iPhones.
                    .frame(height: 150).frame(minWidth: 0, maxWidth: .infinity).clipped()
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 10) {
                            AppIcon(size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "Cofre").cofreFont(.title2).foregroundStyle(.white)
                                Text("Java Edition").cofreFont(.label).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .shadow(color: .black, radius: 0, y: 2)
                        .padding(12)
                    }
                    .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                Text("Java Edition. In your pocket.").cofreFont(.display).foregroundStyle(Color.cofre.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Mods, packs, shaders. All on this device.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
                AdaptiveGrid(minItem: 90, maxColumns: 3) {
                    // Same numbers as the site and README.
                    Stat("4", label: "Steps")
                    Stat("10", label: "Minutes")
                    Stat("1×", label: "Mac visit")
                }
                BlockButton("Set up", role: .primary, size: .large, action: next).keyboardShortcut(.defaultAction)
                Text("Unofficial. Not from Mojang or Microsoft.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: S02 Developer Mode

    private struct DevModeStep: View {
        @Binding var step: Int
        let next: () -> Void
        @Environment(CofreStore.self) private var store
        @Environment(\.scenePhase) private var scenePhase
        var body: some View {
            let s = store.setup.devMode
            StepHeader(
                index: 1, glyph: .shield, title: "Turn on Developer Mode", lede: nil,
                step: $step
            )
            .onChange(of: scenePhase) { _, phase in
                // Back from Settings: check again without a tap.
                if phase == .active { Task { await store.backend.recheckSetup() } }
            }
            Row(
                "Developer Mode",
                trailing: {
                    switch s {
                    case .ready: Badge("On", tone: .success)
                    case .unknown, .checking: Badge("Checking")
                    default: Badge("Off", tone: .danger)
                    }
                })
            ListSection(spacing: 4) {
                Row("Open the Settings app", leading: { RowIndex(1) })
                Row("Privacy & Security", leading: { RowIndex(2) })
                Row("Developer Mode → On", leading: { RowIndex(3) })
                Row("Restart → Turn On (or Enable)", leading: { RowIndex(4) })
            }
            if s.isReady {
                BlockButton("Next", role: .primary, action: next).keyboardShortcut(.defaultAction)
            } else {
                BlockButton("Open Settings", role: .primary) { store.backend.openDeveloperModeSettings() }
                BlockButton("Check again") { Task { await store.backend.recheckSetup() } }
            }
        }
    }

    // MARK: S03 Trust

    private struct TrustStep: View {
        @Binding var step: Int
        let next: () -> Void
        @Environment(CofreStore.self) private var store
        var body: some View {
            let s = store.signing
            StepHeader(
                index: 2, glyph: .shield, title: "Signed for this device", lede: nil, step: $step)
            ListSection(spacing: 4) {
                Row("Installed", leading: { PixelIcon(.check, size: 14) }, trailing: { Meta("OK", tone: .success) })
                Row(
                    "Device registered",
                    leading: { StatusMark(state: s?.deviceRegistered == true ? .ready : .unknown) },
                    trailing: { Meta(s?.deviceRegistered == true ? "Yes" : "—") })
                Row(
                    "Signed by", leading: { StatusMark(state: s == nil ? .unknown : .ready) },
                    trailing: { Meta(s?.team ?? "—") })
                Row(
                    "Works until", leading: { StatusMark(state: s == nil ? .unknown : .ready) },
                    trailing: { Meta(s.map { $0.expires.formatted(date: .abbreviated, time: .omitted) } ?? "—") })
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Asked to trust?").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                Text("Settings › General › VPN & Device Management › Trust").cofreFont(.code).foregroundStyle(
                    Color.cofre.muted)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).block(.well)
            BlockButton("Next", role: .primary, action: next).keyboardShortcut(.defaultAction)
        }
    }

    // MARK: S04 Pairing

    private struct PairingStep: View {
        @Binding var step: Int
        let next: () -> Void
        @Environment(CofreStore.self) private var store
        @Environment(\.widthClass) private var width

        var body: some View {
            let ok = store.setup.pairing.isReady
            StepHeader(
                index: 3, glyph: .key, title: "Connect to a Mac",
                lede: "The key comes here over the cable.", step: $step)
            if ok {
                Banner("Key found", icon: .check, tone: .success)
                if store.pairingFromFile { DeleteCopyNote() }
            } else {
                PairingGuide()
            }
            if case .failed(let msg) = store.setup.pairing { Banner(msg, icon: .cross, tone: .danger) }
            if ok {
                HStack(spacing: 8) {
                    if width > .compact { BlockButton("Back") { step -= 1 }.frame(width: 140) }
                    BlockButton("Next", role: .primary, action: next).keyboardShortcut(.defaultAction)
                }
            }
            if width > .compact {
                HStack(spacing: 10) {
                    Spacer()
                    KeyHint("↩", "continue")
                    KeyHint("esc", "back")
                }
            }
        }
    }

    /// After importing from Files (AirDrop fallback): the copy in Downloads should go.
    struct DeleteCopyNote: View {
        var body: some View {
            Text("Now delete the copy in Files → Downloads.").cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft)
        }
    }

    // MARK: S05 Local VPN

    private struct VPNStep: View {
        @Binding var step: Int
        let next: () -> Void
        @Environment(CofreStore.self) private var store
        var body: some View {
            let s = store.setup.vpn
            StepHeader(
                index: 4, glyph: .shield, title: "Allow local VPN",
                lede: "Lets Cofre turn on JIT by talking to this iPhone. Nothing leaves the phone.", step: $step)
            HStack(spacing: 6) {
                node("Cofre")
                arrow
                node("This iPhone")
            }
            .padding(12).frame(maxWidth: .infinity).block(.well)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Cofre talks to this iPhone. Nothing leaves the phone."))
            ListSection(spacing: 4) {
                Row("Leaves device", trailing: { Meta("Never", tone: .success) })
                Row("Browsing", trailing: { Meta("Untouched", tone: .success) })
            }
            if case .failed(let msg) = s {
                Banner(msg, icon: .cross, tone: .danger)
                Text("Turn off other VPNs (work, ad blocker), then try again.").cofreFont(.secondary).foregroundStyle(
                    Color.cofre.inkSoft)
            }
            if s.isReady {
                BlockButton("Next", role: .primary, action: next).keyboardShortcut(.defaultAction)
            } else {
                BlockButton("Allow VPN", role: .primary, isLoading: s == .checking) { Task { await store.startVPN() } }
                Text("When iOS asks, tap Allow and enter your passcode.").cofreFont(.secondary).foregroundStyle(
                    Color.cofre.muted)
            }
        }
        private func node(_ t: LocalizedStringKey) -> some View {
            Text(t).cofreFont(.buttonS).foregroundStyle(Color.cofre.ink).padding(.horizontal, 10).frame(minHeight: 34)
                .block(.panel)
        }
        private var arrow: some View { Text(verbatim: "→").cofreFont(.button).foregroundStyle(Color.cofre.muted) }
    }

    // MARK: S06 JIT test

    private struct JITTestStep: View {
        @Binding var step: Int
        let next: () -> Void
        @Environment(CofreStore.self) private var store
        var body: some View {
            let s = store.setup.jit
            StepHeader(
                index: 5, glyph: .bolt,
                title: s.isReady ? "JIT works" : s.isFailed ? "JIT didn't turn on" : "Testing JIT",
                lede: "Runs by itself. Needs Wi-Fi, or Airplane Mode for a moment.", step: $step
            )
            .task {
                // Starts by itself; the button below is only for retries.
                // Unstructured, so leaving the step doesn't cancel a test halfway.
                if !store.setup.jit.isReady && !store.jitTesting { Task { await store.testJIT() } }
            }
            JITStepRows()
            if s.isReady, let d = store.device {
                Banner("Ready · \(d.jitMode) · \(d.model) · \(d.os)", icon: .bolt, tone: .success) {
                    Badge("JIT", tone: .success)
                }
            }
            JITFailure()
            if s.isReady {
                BlockButton("Next", role: .primary, action: next).keyboardShortcut(.defaultAction)
            } else if s.isFailed {
                BlockButton("Try again", role: .primary, isLoading: store.jitTesting) { Task { await store.testJIT() } }
            }
        }
    }

    /// A failed JIT test: the message plus what to do for the step that failed (S06, X04).
    struct JITFailure: View {
        @Environment(CofreStore.self) private var store
        var body: some View {
            if case .failed(let msg) = store.setup.jit {
                Banner(msg, icon: .cross, tone: .danger)
                Text(JITStep.Kind.hint(for: store.failedJITStep)).cofreFont(.secondary).foregroundStyle(
                    Color.cofre.inkSoft
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The six JIT steps with their live state (S06, X04).
    struct JITStepRows: View {
        @Environment(CofreStore.self) private var store
        var body: some View {
            let steps =
                store.jitSteps.isEmpty
                ? JITStep.Kind.allCases.map { JITStep(kind: $0, state: store.setup.jit.isReady ? .ready : .unknown) }
                : store.jitSteps
            ListSection(spacing: 4) {
                ForEach(steps, id: \.kind) { s in
                    Row(
                        s.kind.title, leading: { StatusMark(state: s.state).frame(width: 14) },
                        trailing: {
                            Meta(
                                s.detail ?? (s.state.isReady ? s.kind.doneText : ""),
                                tone: s.state.isReady ? .success : nil)
                        }
                    )
                    .dimmed(s.state == .unknown)
                }
            }
        }
    }

    extension JITStep.Kind {
        var title: LocalizedStringKey {
            switch self {
            case .pairing: "Pairing"
            case .vpn: "Local VPN"
            case .diskImage: "Disk image"
            case .debugger: "Debugger"
            case .region: "JIT region"
            case .detach: "Detach"
            }
        }
        /// The next step for a failed test, by the step that failed.
        static func hint(for kind: Self?) -> String {
            switch kind {
            case .pairing:
                String(
                    localized: "Your key may be old. Run the Mac step again: \(CofreLinks.short(CofreLinks.pairing))")
            case .vpn: String(localized: "Turn off other VPNs (work, ad blocker), then try again.")
            case .diskImage: String(localized: "Connect to Wi-Fi. After a restart, JIT needs internet once.")
            case .debugger: String(localized: "Restart this iPhone, open Cofre, then try again.")
            case .region, .detach: String(localized: "Close Cofre fully, open it again, then try again.")
            case nil:
                String(localized: "Use Wi-Fi, or Airplane Mode for a moment, and turn off other VPNs. Then try again.")
            }
        }
        var doneText: String {
            switch self {
            case .pairing: "Valid"
            case .vpn: "On"
            case .diskImage: "Mounted"
            case .debugger: "Attached"
            case .region: "64 MB"
            case .detach: "Done"
            }
        }
    }

    // MARK: S07 Account

    private struct AccountStep: View {
        @Binding var step: Int
        let next: () -> Void
        @Environment(CofreStore.self) private var store
        var body: some View {
            let s = store.setup.account
            StepHeader(
                index: 6, glyph: .head, title: "Sign in",
                lede: "Your account must own Java Edition.", step: $step)
            BlockButton("Sign in with Microsoft", icon: .head, isLoading: s == .checking) {
                Task { await store.signIn() }
            }
            if let a = store.activeAccount, s.isReady {
                Row(
                    a.name, subtitle: "\(a.kind) · owns game", leading: { PixelIcon(.head, size: 26) },
                    trailing: { Badge("OK", tone: .success) })
            }
            if case .failed(let msg) = s { Banner(msg, icon: .cross, tone: .danger) }
            Text("Game files download from Mojang. Never bundled, never shared.").cofreFont(.secondary).foregroundStyle(
                Color.cofre.muted)
            BlockButton("Finish", role: .primary, action: next).disabled(!s.isReady).keyboardShortcut(.defaultAction)
        }
    }

    // MARK: S08 Ready

    private struct ReadyStep: View {
        @Environment(CofreStore.self) private var store
        var body: some View {
            PixelScene(seed: 3, pixels: .init(width: 200, height: 70))
                .frame(height: 120).clipped()
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .overlay(alignment: .bottomLeading) {
                    Badge("Ready · \(store.setup.readyCount)/6 checks", tone: .success, big: true).padding(12)
                }
            Text("You're set.").cofreFont(.display).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
            Text("Tap Play. JIT runs by itself.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
            ListSection(spacing: 4) {
                Row(
                    "Developer Mode", leading: { PixelIcon(.check, size: 14) }, trailing: { Meta("On", tone: .success) }
                )
                Row(
                    "Pairing · VPN · JIT", leading: { PixelIcon(.check, size: 14) },
                    trailing: { Meta("OK", tone: .success) })
                if let a = store.activeAccount {
                    Row(
                        a.name, leading: { PixelIcon(.check, size: 14) },
                        trailing: { Meta("Signed in", tone: .success) })
                }
            }
            Banner(
                "Tip: iOS updates break pairing. Settings › General › Software Update › Automatic Updates: Off.",
                icon: .book, tone: .warn)
            BlockButton("Play", icon: .play, role: .primary, size: .large) { store.finishSetup() }
                .keyboardShortcut(.defaultAction)
        }
    }
#endif
