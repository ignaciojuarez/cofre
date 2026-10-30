#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import UserNotifications

    // G01 Game stopped: Cofre's screen when Minecraft exits mid-game, in place of Air's crash screen. A card over the
    // lake: what happened, one next step, Close Cofre. Share log and Details (with Copy) come after. Side by
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

    /// The whole screen for a hosting controller: measures its window like `CofreRootView`.
    public struct GameExitView: View {
        let report: GameExitReport, intent: RejoinIntent?, reportURL: URL?, reportPreview: ReportPreviewData?, close: () -> Void, retry: () -> Void, showDetails: Bool
        let turnShadersOff: (() throws -> Void)?
        /// `showDetails` opens Details right away (preview host). `turnShadersOff` is set when shaders likely caused the crash.
        public init(report: GameExitReport, intent: RejoinIntent? = nil, reportURL: URL? = nil, reportPreview: ReportPreviewData? = nil, showDetails: Bool = false, close: @escaping () -> Void, retry: (() -> Void)? = nil, turnShadersOff: (() throws -> Void)? = nil) {
            self.turnShadersOff = turnShadersOff
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
                GameExitScreen(report: report, intent: intent, reportURL: reportURL, reportPreview: reportPreview, size: g.size, close: close, retry: retry, turnShadersOff: turnShadersOff, showDetails: showDetails).sizeClasses(
                    SizeClasses(g.size))
            }
            .preferredColorScheme(.dark)
            .tint(Color.cofre.accent)
        }
    }

    struct GameExitScreen: View {
        let report: GameExitReport, intent: RejoinIntent?, reportURL: URL?, reportPreview: ReportPreviewData?, size: CGSize, close: () -> Void, retry: () -> Void
        let turnShadersOff: (() throws -> Void)?
        @State var showDetails = false
        @State private var shadersOff = false
        @State private var copied = false
        @State private var showReportShare = false

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
                Text(verbatim: report.nextStep).cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
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
            if let intent {
                BlockButton("Play again · \(intent.displayName)", role: .primary, size: .large) {
                    let content = UNMutableNotificationContent()
                    content.body = "Tap to jump back into \(intent.displayName)"
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cofre.rejoin", content: content, trigger: nil))
                    retry()
                }
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
                    ShareLink(items: report.files) { Text("Share log") }.buttonStyle(.block()).disabled(report.files.isEmpty)
                }
                BlockButton("Details") { showDetails = true }
            }
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader("Details") {
                    BlockButton(copied ? "Copied" : "Copy", size: .small, fullWidth: false) {
                        UIPasteboard.general.string = report.detailsText
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
