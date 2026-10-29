#if canImport(UIKit)
import SwiftUI

// P02 Launch. FullScreenTakeover + AdaptiveSplit(.stack): scene and XP bar beside the stages and live log;
// stacked on compact with the log behind a button.

public struct LaunchScreen: View {
    @Environment(CofreStore.self) private var store
    @Environment(NavModel.self) private var nav
    public init() {}

    public var body: some View {
        AdaptiveSplit(primaryMin: 420, secondaryWidth: 440, fallback: .stack) {
            LaunchHero()
        } secondary: {
            LaunchStages()
        }
        .background(Color.cofre.page.ignoresSafeArea())
        .onKeyPress(.escape) { Task { await store.cancelLaunch() }; nav.showingLaunch = false; return .handled }
    }
}

private struct LaunchHero: View {
    @Environment(CofreStore.self) private var store
    @Environment(\.widthClass) private var width

    var body: some View {
        let p = store.launch, inst = store.activeInstance
        ZStack(alignment: .bottomLeading) {
            PixelScene(seed: 7, pixels: .init(width: 200, height: 140)).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                if let inst { Text(verbatim: "\(inst.name) · \(inst.loaderLabel)").cofreFont(.label).foregroundStyle(.white.opacity(0.85)) }
                Text(title(p)).cofreFont(.display).foregroundStyle(.white).shadow(color: .black, radius: 0, y: 2)
                    .accessibilityAddTraits(.isHeader)
                ProgressView(value: p?.fraction ?? 0).progressViewStyle(.xp())
                if let p {
                    Text(verbatim: "Step \(p.stage) of \(p.of)" + (p.detail.map { " · \($0)" } ?? ""))
                        .cofreFont(.label).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(width == .compact ? 20 : 32)
            .padding(.bottom, width == .compact ? 0 : 4)
        }
        .frame(minHeight: width == .compact ? 300 : nil)
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func title(_ p: LaunchProgress?) -> LocalizedStringKey {
        if store.launchError != nil { return "Launch failed" }
        return p?.finished == true ? "In game" : "Launching…"
    }
}

private struct LaunchStages: View {
    @Environment(CofreStore.self) private var store
    @Environment(NavModel.self) private var nav
    @Environment(\.widthClass) private var width
    @State private var showLog = false

    static let stageNames = ["JIT", "Java 21", "Libraries", "Assets", "Mods", "Renderer · MobileGlues", "First frame", "In game"]

    var body: some View {
        let p = store.launch
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ListSection("Stages", spacing: 4) {
                        ForEach(Array(Self.stageNames.enumerated()), id: \.offset) { i, name in
                            let n = i + 1, cur = p?.stage ?? 0
                            let state: CheckState = n < cur || p?.finished == true ? .ready : n == cur ? (store.launchError != nil ? .failed("") : .checking) : .unknown
                            Row(name, leading: { StatusMark(state: state).frame(width: 14) }, trailing: {
                                if n == cur, let f = p?.fraction, p?.finished != true { Meta("\(Int(f * 100))%") }
                            })
                            .dimmed(state == .unknown)
                        }
                    }
                    if let err = store.launchError { Banner(err, icon: .cross, tone: .danger) }
                    if width != .compact {
                        ListSection("Log") { LogView(lines: store.launchLog).frame(minHeight: 180) }
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.top, 20)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep Cofre open while it loads.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                HStack(spacing: 8) {
                    if width == .compact {
                        BlockButton("Log") { showLog = true }.keyboardShortcut("l", modifiers: .command)
                    } else {
                        BlockButton("Copy log") {
                            UIPasteboard.general.string = store.launchLog.map { "\($0.time) [\($0.tag)] \($0.text)" }.joined(separator: "\n")
                        }
                    }
                    if p?.finished == true || store.launchError != nil {
                        BlockButton("Close", role: .primary) { store.launch = nil; nav.showingLaunch = false }
                    } else {
                        BlockButton("Cancel") { Task { await store.cancelLaunch(); nav.showingLaunch = false } }
                            .keyboardShortcut(".", modifiers: .command)
                    }
                }
            }
            .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 16)
        }
        .blockSheet(isPresented: $showLog) {
            VStack(spacing: 10) {
                SheetHeader("Log")
                LogView(lines: store.launchLog).padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }
}
#endif
