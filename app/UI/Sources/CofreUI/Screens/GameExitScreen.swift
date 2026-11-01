#if canImport(UIKit)
    import SwiftUI
    import CofreKit
    import UIKit
    import UserNotifications

    // G01 Game stopped: Cofre's screen when Minecraft exits mid-game, in place of Air's crash screen. A card over the
    // lake: what happened, one next step, Close Cofre. Share report and Details (with Copy) come after. Side by
    // side in iPhone landscape (where the game runs), stacked in portrait and on iPad.

    /// Java can't start twice in one process, and iOS has no relaunch (Air's Restart only exits), so closing goes to
    /// the Home Screen and ends the process, like Air's own exit.
    public enum AppExit {
        @MainActor public static func close() {
            NSLog("[Cofre] game exit: closing Cofre")
            UIApplication.shared.perform(NSSelectorFromString("suspend"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        }
    }

    /// The crash named a mod that isn't installed ("needs language provider kotlinforforge"): Get puts it in that
    /// instance, then Play again.
    public struct GameExitFix {
        /// "Kotlin for Forge".
        public let name: String
        public let install: @MainActor () async throws -> Void
        public init(name: String, install: @escaping @MainActor () async throws -> Void) {
            self.name = name
            self.install = install
        }
    }

    /// "Turn off Distant Horizons": the mod the crash named, when its file is in the instance's mods folder.
    public struct GameExitTurnOff {
        public let name: String
        public let turnOff: () throws -> Void
        public init(name: String, turnOff: @escaping () throws -> Void) {
            self.name = name
            self.turnOff = turnOff
        }
    }

    /// The whole screen for a hosting controller: measures its window like `CofreRootView`.
    public struct GameExitView: View {
        let report: GameExitReport, intent: RejoinIntent?, reportURL: URL?, reportPreview: ReportPreviewData?, close: () -> Void, retry: () -> Void, showDetails: Bool
        let turnShadersOff: (() throws -> Void)?
        let fix: GameExitFix?
        let turnModOff: GameExitTurnOff?
        /// `showDetails` opens Details right away (preview host). `turnShadersOff` is set when shaders likely caused the crash.
        public init(report: GameExitReport, intent: RejoinIntent? = nil, reportURL: URL? = nil, reportPreview: ReportPreviewData? = nil, showDetails: Bool = false, close: @escaping () -> Void, retry: (() -> Void)? = nil, turnShadersOff: (() throws -> Void)? = nil, fix: GameExitFix? = nil, turnModOff: GameExitTurnOff? = nil) {
            self.turnShadersOff = turnShadersOff
            self.turnModOff = turnModOff
            self.fix = fix
            self.report = report
            self.intent = intent
            self.reportURL = reportURL
            self.reportPreview = reportPreview
            self.close = close
            self.retry = retry ?? close
            self.showDetails = showDetails
        }

        public var body: some View {
            GeometryReader { g in
                GameExitScreen(report: report, intent: intent, reportURL: reportURL, reportPreview: reportPreview, size: g.size, close: close, retry: retry, turnShadersOff: turnShadersOff, fix: fix, turnModOff: turnModOff, showDetails: showDetails).sizeClasses(
                    SizeClasses(g.size))
            }
            .preferredColorScheme(.dark)
            .tint(Color.cofre.accent)
        }
    }

    struct GameExitScreen: View {
        let report: GameExitReport, intent: RejoinIntent?, reportURL: URL?, reportPreview: ReportPreviewData?, size: CGSize, close: () -> Void, retry: () -> Void
        let turnShadersOff: (() throws -> Void)?
        var fix: GameExitFix? = nil
        var turnModOff: GameExitTurnOff? = nil
        @State var showDetails = false
        @State private var fixState = FixState.idle
        @State private var shadersOff = false
        @State private var modOff = false
        @State private var copied = false
        @State private var showReportShare = false

        enum FixState: Equatable { case idle, working, done, failed(String) }
        /// Get (or Turn off) comes first until it's done; then Play again does.
        private var fixPending: Bool { fix != nil && fixState != .done || turnModOff != nil && !modOff }

        /// iPhone landscape: short and wide, so text and actions sit side by side.
        private var sideBySide: Bool { size.width >= 600 && size.height < 500 }

        var body: some View {
            ZStack {
                PixelScene(seed: 7, pixels: .init(width: 240, height: 160)).ignoresSafeArea()
                LinearGradient(
                    colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea().accessibilityHidden(true)
                ScrollView {
                    card
                        .padding(sideBySide ? 20 : 24)
                        .frame(maxWidth: sideBySide ? 720 : 500)
                        .background(BlockBackground(.panel, lip: 4))
                        .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
                        .padding(.horizontal, 16).padding(.vertical, sideBySide ? 12 : 24)
                        .frame(maxWidth: .infinity, minHeight: size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .environment(\.widthClass, sideBySide || size.width >= 700 ? .medium : .compact)
            .blockSheet(isPresented: $showDetails) { details }
            .blockSheet(isPresented: $showReportShare) { if let reportURL, let reportPreview { ReportPreviewSheet(preview: reportPreview, url: reportURL) } }
        }

        @ViewBuilder private var card: some View {
            if sideBySide {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) { message }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) { actions }.frame(width: 250)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    message
                    VStack(spacing: 8) { actions }.padding(.top, 4)
                }
            }
        }

        @ViewBuilder private var message: some View {
            HStack(spacing: 12) {
                PixelIcon(.head, size: 26)
                    .frame(width: 48, height: 48)
                    .background(BlockBackground(.tinted(report.reason == .quit ? .accent : .warn)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: report.title).cofreFont(.title).foregroundStyle(Color.cofre.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let instance = report.instance {
                        Text(verbatim: instance).cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    }
                }
            }
            Text(verbatim: report.explanation).cofreFont(.body).foregroundStyle(Color.cofre.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Next step")
                Text(verbatim: fix.map { "Get \($0.name) for this instance, then play again." }
                    ?? turnModOff.map { "Turn off \($0.name), then play again." } ?? report.nextStep).cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlockBackground(.well))
        }

        @ViewBuilder private var actions: some View {
            if let turnShadersOff {
                if shadersOff {
                    Banner("Shaders are off. Play again to try without them; turn them back on in game.", icon: .check, tone: .success)
                } else {
                    BlockButton("Turn shaders off", size: .large) {
                        shadersOff = (try? turnShadersOff()) != nil
                    }
                }
            }
            if let turnModOff {
                if modOff {
                    Banner("\(turnModOff.name) is off. Play again to try without it.", icon: .check, tone: .success)
                } else {
                    BlockButton("Turn off \(turnModOff.name)", role: .primary, size: .large) {
                        modOff = (try? turnModOff.turnOff()) != nil
                    }
                }
            }
            if let fix {
                switch fixState {
                case .done:
                    Banner("\(fix.name) is installed. Play again to load it.", icon: .check, tone: .success)
                case .failed(let reason):
                    Banner(reason, icon: .cross, tone: .danger)
                    getButton(fix)
                case .idle, .working:
                    getButton(fix)
                }
            }
            if let intent {
                BlockButton("Play again · \(intent.displayName)", role: fixPending ? .secondary : .primary, size: .large) {
                    let content = UNMutableNotificationContent()
                    content.body = "Tap to jump back into \(intent.displayName)"
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cofre.rejoin", content: content, trigger: nil))
                    retry()
                }
                BlockButton("Close Cofre", role: .ghost, size: .large, action: close)
            } else if fix != nil || turnModOff != nil {
                // Play again closes Cofre too (Java runs once per launch); the name says what it's for.
                BlockButton("Play again", role: fixPending ? .secondary : .primary, size: .large, action: retry)
                BlockButton("Close Cofre", role: .ghost, size: .large, action: close)
            } else {
                BlockButton("Close Cofre", role: .primary, size: .large, action: close)
            }
            // Honest about restarts: Java can't start twice in one app run.
            Text("Minecraft runs once per launch. Open Cofre again to play.")
                .cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            HStack(spacing: 8) {
                if reportURL != nil {
                    BlockButton("Share report", icon: .paper) { showReportShare = true }
                } else {
                    Text("Report unavailable").cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                }
                BlockButton("Details") { showDetails = true }
            }
        }

        private func getButton(_ fix: GameExitFix) -> some View {
            BlockButton("Get \(fix.name)", icon: .chest, role: .primary, size: .large, isLoading: fixState == .working) {
                guard fixState != .working else { return }
                fixState = .working
                Task {
                    do {
                        try await fix.install()
                        fixState = .done
                    } catch {
                        fixState = .failed(error.localizedDescription)
                    }
                }
            }
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader("Details") {
                    BlockButton(copied ? "Copied" : "Copy", size: .small, fullWidth: false) {
                        UIPasteboard.general.string = ReportBundle.redact(report.detailsText)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Row("Exit code", trailing: { Meta("\(report.code)") })
                    if let clue = report.clue {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Clue")
                            Text(verbatim: clue).cofreFont(.code).foregroundStyle(Color.cofre.ink).textSelection(
                                .enabled)
                        }
                    }
                    if let crash = report.files.dropFirst().first {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Crash report")
                            Text(verbatim: crash.lastPathComponent).cofreFont(.code).foregroundStyle(Color.cofre.ink)
                        }
                    }
                    SectionLabel("Log")
                    LogView(
                        lines: report.logTail.enumerated().map { i, text in
                            LogLine(
                                id: i, time: "", tag: "Log", text: text,
                                level: GameExitReport.isError(text) ? .error : .info)
                        }
                    )
                    .frame(minHeight: 200)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }
#endif
