#if canImport(UIKit)
    import SwiftUI
    import UIKit

    // G01 Game stopped: Cofre's screen when Minecraft exits mid-game, in place of Air's crash screen. A card over the
    // lake: what happened, one next step, Close Cofre. Share log, Copy details and the raw log come after. Side by
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
        let report: GameExitReport, close: () -> Void, showDetails: Bool
        /// `showDetails` opens Details right away (preview host).
        public init(report: GameExitReport, showDetails: Bool = false, close: @escaping () -> Void) {
            self.report = report
            self.close = close
            self.showDetails = showDetails
        }

        public var body: some View {
            GeometryReader { g in
                GameExitScreen(report: report, size: g.size, close: close, showDetails: showDetails).sizeClasses(
                    SizeClasses(g.size))
            }
            .environment(\.cofreTheme, CofreTheme.current)
            .preferredColorScheme(CofreTheme.current.colorScheme)
            .tint(Color.cofre.accent)
        }
    }

    struct GameExitScreen: View {
        let report: GameExitReport, size: CGSize, close: () -> Void
        @State var showDetails = false
        @State private var copied = false

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
            BlockButton("Close Cofre", role: .primary, size: .large, action: close)
            // Honest about restarts: Java can't start twice in one app run.
            Text("Minecraft can only start once each time Cofre opens. Open Cofre again from the Home Screen to play.")
                .cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            HStack(spacing: 8) {
                ShareLink(items: report.files) { Text("Share log") }.buttonStyle(.block())
                    .disabled(report.files.isEmpty)
                BlockButton(copied ? "Copied" : "Copy details") {
                    UIPasteboard.general.string = report.detailsText
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
            }
            BlockButton("Details", role: .ghost) { showDetails = true }
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader("Details")
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
