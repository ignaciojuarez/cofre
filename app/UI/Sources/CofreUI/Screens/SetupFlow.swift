#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers

// S01–S08. Six checks, one per `SetupState` field. Each step checks itself and moves on when it passes.
// CenteredCard: full screen on compact, a 560 pt card over a scene on regular.

public struct SetupFlow: View {
    @Environment(CofreStore.self) private var store
    @State private var step: Int
    private let startAt: Int?

    static let stepNames: [LocalizedStringKey] = ["Dev Mode", "Trust", "Pairing", "VPN", "JIT", "Account"]

    /// `startAt`: 0 = welcome, 1…6 = checks, 7 = ready. `nil` resumes at the first check that isn't ready.
    public init(startAt: Int? = nil) { self.startAt = startAt; _step = State(initialValue: startAt ?? 0) }

    public var body: some View {
        CenteredCard(scene: UInt32(7 + step)) {
            Group {
                switch step {
                case 0: WelcomeStep(next: { go(firstOpen) })
                case 1: DevModeStep(step: $step)
                case 2: TrustStep(step: $step)
                case 3: PairingStep(step: $step)
                case 4: VPNStep(step: $step)
                case 5: JITTestStep(step: $step)
                case 6: AccountStep(step: $step)
                default: ReadyStep()
                }
            }
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.15), value: step)
        .onAppear { if startAt == nil, store.setup.readyCount > 0 { step = firstOpen } }
    }

    private var firstOpen: Int { (store.setup.all.firstIndex { !$0.isReady } ?? 6) + 1 }
    private func go(_ s: Int) { step = s }
}

/// Header shared by S02–S07: back, counter, StepBar, icon, kicker, title, lede.
private struct StepHeader: View {
    let index: Int, glyph: PixelGlyph, kicker: LocalizedStringKey, title: LocalizedStringKey, lede: LocalizedStringKey?
    @Binding var step: Int
    @Environment(\.widthClass) private var width

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { step -= 1 } label: {
                    Text(verbatim: "‹").cofreFont(.header).foregroundStyle(Color.cofre.accent).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain).keyboardShortcut(.escape, modifiers: []).accessibilityLabel(Text("Back"))
                Spacer()
                Meta("\(index)/6")
            }
            .padding(.vertical, -8)
            StepBar(steps: SetupFlow.stepNames, current: index - 1)
            PixelIcon(glyph, size: 44).padding(.top, 6)
            (Text(verbatim: String(format: "Step %02d · ", index)) + Text(kicker))
                .cofreFont(.label).foregroundStyle(Color.cofre.muted)
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
                .frame(height: 150).clipped()
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
            Text("Java Edition. In your pocket.").cofreFont(.display).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
            Text("Mods, packs, shaders. All on this device.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
            AdaptiveGrid(minItem: 90, maxColumns: 3) {
                Stat("6", label: "Checks"); Stat("5", label: "Minutes"); Stat("1×", label: "Computer")
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
    @Environment(CofreStore.self) private var store
    var body: some View {
        let on = store.setup.devMode.isReady
        StepHeader(index: 1, glyph: .shield, kicker: "Developer Mode", title: "Turn on Developer Mode", lede: nil, step: $step)
        Row("Developer Mode", trailing: { Badge(on ? "On" : "Off", tone: on ? .success : .danger) })
        ListSection(spacing: 4) {
            Row("Open Settings", leading: { RowIndex(1) }, trailing: { Chevron() })
            Row("Privacy & Security", leading: { RowIndex(2) }, trailing: { Chevron() })
            Row("Developer Mode → On", leading: { RowIndex(3) })
            Row("Restart → Turn On", leading: { RowIndex(4) })
        }
        Text("No toggle yet? Do the Mac step first, then come back.").cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
        if on {
            BlockButton("Next", role: .primary) { step += 1 }.keyboardShortcut(.defaultAction)
        } else {
            BlockButton("Open Settings", role: .primary) { store.backend.openDeveloperModeSettings() }
            BlockButton("Check again") { Task { await store.backend.recheckSetup() } }
        }
    }
}

// MARK: S03 Trust

private struct TrustStep: View {
    @Binding var step: Int
    @Environment(CofreStore.self) private var store
    var body: some View {
        let s = store.signing
        StepHeader(index: 2, glyph: .shield, kicker: "Trust", title: "Signed for this device", lede: nil, step: $step)
        ListSection(spacing: 4) {
            Row("Installed", leading: { PixelIcon(.check, size: 14) }, trailing: { Meta("OK", tone: .success) })
            Row("Device registered", leading: { StatusMark(state: s?.deviceRegistered == true ? .ready : .unknown) },
                trailing: { Meta(s?.deviceRegistered == true ? "Yes" : "—") })
            Row("Signed by", leading: { PixelIcon(.check, size: 14) }, trailing: { Meta(s?.team ?? "—") })
            Row("Works until", leading: { PixelIcon(.check, size: 14) },
                trailing: { Meta(s.map { $0.expires.formatted(date: .abbreviated, time: .omitted) } ?? "—") })
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Asked to trust?").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
            Text("Settings › General › VPN & Device Management › Trust").cofreFont(.code).foregroundStyle(Color.cofre.muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).block(.well)
        BlockButton("Next", role: .primary) { step += 1 }.keyboardShortcut(.defaultAction)
    }
}

// MARK: S04 Pairing

private struct PairingStep: View {
    @Binding var step: Int
    @Environment(CofreStore.self) private var store
    @Environment(\.widthClass) private var width
    @State private var choosing = false

    var body: some View {
        let ok = store.setup.pairing.isReady
        StepHeader(index: 3, glyph: .key, kicker: "Pairing key", title: "Connect to a Mac",
                   lede: "Run one command on a Mac with this device plugged in. The key comes straight here.", step: $step)
        if ok {
            Banner("Key found", icon: .check, tone: .success)
        } else {
            PairingGuide()
        }
        if case .failed(let msg) = store.setup.pairing { Banner(msg, icon: .cross, tone: .danger) }
        HStack(spacing: 8) {
            if width > .compact { BlockButton("Back") { step -= 1 }.frame(width: 140) }
            if ok {
                BlockButton("Next", role: .primary) { step += 1 }.keyboardShortcut(.defaultAction)
            } else {
                BlockButton("I have a file", icon: .paper, role: .ghost, fullWidth: false) { choosing = true }
                Spacer(minLength: 0)
            }
        }
        HStack(spacing: 10) {
            Text("Stays on this device. Never share it.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
            if width > .compact { Spacer(); KeyHint("↩", "continue"); KeyHint("esc", "back") }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: UTType.pairingFiles + [.data]) { r in
            if let (_, data) = readPicked(r.map { [$0] }) { store.importPairing(data) }
        }
    }
}

// MARK: S05 Local VPN

private struct VPNStep: View {
    @Binding var step: Int
    @Environment(CofreStore.self) private var store
    var body: some View {
        let s = store.setup.vpn
        StepHeader(index: 4, glyph: .shield, kicker: "Local VPN", title: "Allow local VPN", lede: "Lets Cofre reach this device's debugger.", step: $step)
        HStack(spacing: 6) {
            node("App"); arrow; node("Loop"); arrow; node("10.7.0.1")
        }
        .padding(12).frame(maxWidth: .infinity).block(.well)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Traffic goes from the app to a loopback tunnel at 10.7.0.1"))
        ListSection(spacing: 4) {
            Row("Leaves device", trailing: { Meta("Never", tone: .success) })
            Row("Browsing", trailing: { Meta("Untouched", tone: .success) })
        }
        if case .failed(let msg) = s { Banner(msg, icon: .cross, tone: .danger) }
        if s.isReady {
            BlockButton("Next", role: .primary) { step += 1 }.keyboardShortcut(.defaultAction)
        } else {
            BlockButton("Allow VPN", role: .primary, isLoading: s == .checking) { Task { await store.startVPN() } }
        }
    }
    private func node(_ t: LocalizedStringKey) -> some View {
        Text(t).cofreFont(.buttonS).foregroundStyle(Color.cofre.ink).padding(.horizontal, 10).frame(minHeight: 34).block(.panel)
    }
    private var arrow: some View { Text(verbatim: "→").cofreFont(.button).foregroundStyle(Color.cofre.muted) }
}

// MARK: S06 JIT test

private struct JITTestStep: View {
    @Binding var step: Int
    @Environment(CofreStore.self) private var store
    var body: some View {
        let ready = store.setup.jit.isReady
        StepHeader(index: 5, glyph: .bolt, kicker: "JIT test", title: ready ? "JIT works" : "Testing JIT", lede: nil, step: $step)
        JITStepRows()
        if ready, let d = store.device {
            Banner("Ready · \(d.jitMode) · \(d.model) · \(d.os)", icon: .bolt, tone: .success) { Badge("JIT", tone: .success) }
        }
        if case .failed(let msg) = store.setup.jit { Banner(msg, icon: .cross, tone: .danger) }
        if ready {
            BlockButton("Next", role: .primary) { step += 1 }.keyboardShortcut(.defaultAction)
        } else {
            BlockButton("Test JIT", role: .primary, isLoading: store.jitTesting) { Task { await store.testJIT() } }
        }
    }
}

/// The six JIT steps with their live state (S06, X04).
struct JITStepRows: View {
    @Environment(CofreStore.self) private var store
    var body: some View {
        let steps = store.jitSteps.isEmpty
            ? JITStep.Kind.allCases.map { JITStep(kind: $0, state: store.setup.jit.isReady ? .ready : .unknown) }
            : store.jitSteps
        ListSection(spacing: 4) {
            ForEach(steps, id: \.kind) { s in
                Row(s.kind.title, leading: { StatusMark(state: s.state).frame(width: 14) }, trailing: {
                    Meta(s.detail ?? (s.state.isReady ? s.kind.doneText : ""), tone: s.state.isReady ? .success : nil)
                })
                .dimmed(s.state == .unknown)
            }
        }
    }
}

extension JITStep.Kind {
    var title: LocalizedStringKey {
        switch self { case .pairing: "Pairing"; case .vpn: "Local VPN"; case .diskImage: "Disk image"
        case .debugger: "Debugger"; case .region: "JIT region"; case .detach: "Detach" }
    }
    var doneText: String {
        switch self { case .pairing: "Valid"; case .vpn: "On"; case .diskImage: "Mounted"; case .debugger: "Attached"; case .region: "64 MB"; case .detach: "Done" }
    }
}

// MARK: S07 Account

private struct AccountStep: View {
    @Binding var step: Int
    @Environment(CofreStore.self) private var store
    var body: some View {
        let s = store.setup.account
        StepHeader(index: 6, glyph: .head, kicker: "Account", title: "Sign in", lede: "Your account must own Java Edition.", step: $step)
        BlockButton("Sign in with Microsoft", icon: .head, isLoading: s == .checking) { Task { await store.signIn() } }
        if let a = store.activeAccount, s.isReady {
            Row(a.name, subtitle: "\(a.kind) · owns game", leading: { PixelIcon(.head, size: 26) }, trailing: { Badge("OK", tone: .success) })
        }
        if case .failed(let msg) = s { Banner(msg, icon: .cross, tone: .danger) }
        Text("Game files download from Mojang. Never bundled, never shared.").cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
        BlockButton("Finish", role: .primary) { step += 1 }.disabled(!s.isReady).keyboardShortcut(.defaultAction)
    }
}

// MARK: S08 Ready

private struct ReadyStep: View {
    @Environment(CofreStore.self) private var store
    var body: some View {
        PixelScene(seed: 3, pixels: .init(width: 200, height: 70))
            .frame(height: 120).clipped()
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .overlay(alignment: .bottomLeading) { Badge("Ready · \(store.setup.readyCount)/6 checks", tone: .success, big: true).padding(12) }
        Text("You're set.").cofreFont(.display).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
        Text("Tap Play. JIT runs by itself.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
        ListSection(spacing: 4) {
            Row("Developer Mode", leading: { PixelIcon(.check, size: 14) }, trailing: { Meta("On", tone: .success) })
            Row("Pairing · VPN · JIT", leading: { PixelIcon(.check, size: 14) }, trailing: { Meta("OK", tone: .success) })
            if let a = store.activeAccount {
                Row(a.name, leading: { PixelIcon(.check, size: 14) }, trailing: { Meta("Signed in", tone: .success) })
            }
        }
        Banner("Tip: iOS updates break pairing. Settings › General › Software Update › Automatic Updates: Off.", icon: .book, tone: .warn)
        BlockButton("Play", icon: .play, role: .primary, size: .large) { store.setupDismissed = true }
            .keyboardShortcut(.defaultAction)
    }
}
#endif
