import CofreUI
import SwiftUI

// Design review: cleaner versions of the overnight surfaces, for the owner to approve before they're ported into
// app/UI/Sources. Each uses CofreUI's public components and sits over the real screens where context matters.
// Launch with `-review <name>` (see PreviewHost.swift).

enum DesignReview {
    @MainActor @ViewBuilder
    static func view(_ name: String, store: CofreStore, nav: NavModel, setupStep: Int?) -> some View {
        let real = CofreRootView(store: store, nav: nav, setupStart: setupStep)
        let reason = UserDefaults.standard.string(forKey: "exitReason") ?? "metalReload"
        let loader = UserDefaults.standard.string(forKey: "loaderError") ?? "forge"
        Group {
            switch name {
            case "join": JoinServerClean.Preview(real: real, server: "play.example.net:25565", nav: nav)
            case "joinEmpty": JoinServerClean.Preview(real: real, server: "", nav: nav)
            case "rename": RenameClean.Preview(real: real, nav: nav, store: store)
            case "modWarning": ModWarningClean.Preview(real: real, nav: nav)
            case "data": DataPacksClean.Preview(real: real, nav: nav, store: store)
            case "resolution": ResolutionClean.Preview(real: real, nav: nav)
            case "controls": ControlsClean.Preview(nav: nav)
            case "exit": GameExitClean.Preview(reason: reason)
            case "loaderError": LoaderErrorClean.Preview(kind: loader)
            case "onboarding": OnboardingClean.Preview()
            default: real
            }
        }
        .environment(store).environment(nav)
        .preferredColorScheme(.dark)
        .tint(Color.cofre.accent)
    }

    /// Today's loader-install errors (`clean: false`) and the proposed copy.
    static func loaderError(_ kind: String, clean: Bool) -> String {
        switch (kind, clean) {
        case ("pairing", false): "No pairing key yet. Pair this device in Settings first."
        case ("pairing", true): "This device isn't paired yet."
        case (_, false): "Close Cofre completely and open it again to install another Forge or NeoForge loader."
        default: "Reopen Cofre to install another loader."
        }
    }

    /// A Metal crash in the GPU driver right after Mipmap levels changed in game.
    static var metalReloadReport: GameExitReport {
        let log = """
            [17:41:52] [Render thread/INFO]: Loaded 1287 recipes
            [17:41:58] [Render thread/INFO]: Reloading ResourceManager: vanilla, fabric
            [17:42:09] Thread 14 Crashed: AGXMetalG16X 0x1c2f0 -[AGXG16XFamilyRenderContext drawPrimitives]
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("latestlog.txt")
        try? log.write(to: url, atomically: true, encoding: .utf8)
        return GameExitReport(
            code: -1, crashReport: nil, log: log, instance: "Survival+ · Fabric 26.3", files: [url],
            changedSettings: ["Mipmap levels"])
    }
}

extension View {
    /// Size classes from the window, as `CofreRootView` measures them (`SizeClasses`): regular from 700 pt wide.
    func measuredSizeClasses() -> some View { modifier(MeasuredSizeClasses()) }
}

private struct MeasuredSizeClasses: ViewModifier {
    @State private var size = CGSize.zero
    func body(content: Content) -> some View {
        content
            .environment(\.horizontalSizeClass, size.width >= 700 ? .regular : .compact)
            .environment(\.verticalSizeClass, size.height >= 500 ? .regular : .compact)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }
}

/// The Join server card on regular width: a dimmed window and a centered block card, like `JoinServerCard`.
struct ReviewCard<C: View>: View {
    var width: CGFloat = 440
    @ViewBuilder let content: C
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            content
                .frame(width: width)
                .background(Color.cofre.page)
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
        }
    }
}

extension View {
    /// Presents `content` like the real app after a moment. Cofre's root calls a window 700 pt or wider regular
    /// (iPads, big iPhones in landscape): there the Join sheet is a centered card (`card: true`), and a hugging block
    /// sheet is 420 pt wide. Under 700 pt both are bottom sheets.
    func reviewSheet<C: View>(card: Bool = false, when ready: Bool = true, @ViewBuilder content: @escaping () -> C)
        -> some View
    {
        modifier(ReviewSheet(card: card, ready: ready, sheet: content))
    }
}

private struct ReviewSheet<C: View>: ViewModifier {
    let card: Bool, ready: Bool
    @ViewBuilder let sheet: () -> C
    @State private var shown = false
    @State private var regular = false
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { regular = $0 }
            .overlay { if card && regular && shown { ReviewCard { sheet() } } }
            .blockSheet(isPresented: Binding(get: { shown && !(card && regular) }, set: { shown = $0 }), hugsContent: true) {
                sheet().frame(maxWidth: regular ? 420 : .infinity)
            }
            .task(id: ready) {
                guard ready else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                shown = true
            }
    }
}
