#if canImport(UIKit)
    import SwiftUI

    // Join server sheet (GAP-14). Mockup: `cofre-design/server-join/popup.html`. Contract: POPUP_CONTRACT.md.
    // A bottom sheet that hugs its content on compact; a centered card up to 560 pt on regular. Header and footer stay
    // put while the middle scrolls. One primary button per state. Closing it never stops an install.

    public struct JoinServerSheet: View {
        /// Bottom sheet that hugs its content, or a centered card up to 560 pt.
        public enum Style: Sendable { case bottomSheet, card }

        private let request: ServerJoinRequest?
        private let fixed: (any ServerJoinViewModel)?
        private let style: Style?
        @Environment(CofreStore.self) private var store: CofreStore?
        @Environment(\.horizontalSizeClass) private var sizeClass
        @State private var unavailable = false

        /// Presented by the root for `NavModel.serverJoin`. Reuses the store's live model, so a running install shows.
        /// Pass the presenting window's style: inside a sheet, iPad reports a compact size class.
        public init(request: ServerJoinRequest, style: Style? = nil) {
            self.request = request
            fixed = nil
            self.style = style
        }
        /// A given model (tests, previews). `nil` style reads the size class.
        public init(model: any ServerJoinViewModel, style: Style? = nil) {
            request = nil
            fixed = model
            self.style = style
        }

        public var body: some View {
            let card = (style ?? (sizeClass == .regular ? .card : .bottomSheet)) == .card
            Group {
                if let request, request.card == nil, request.pin == nil, !request.discoverCard {
                    PlainServerJoinView(request: request)
                } else if let model = fixed ?? request.flatMap({ store?.serverJoins[$0.id] }) {
                    JoinSheetModelView(model: model, card: card)
                } else {
                    let server = ServerSummary(
                        id: request?.id ?? "", name: request?.server ?? "", address: request?.server ?? "")
                    JoinSheetFrame(
                        server: server, state: unavailable ? Self.unavailableState : .resolving, card: card,
                        send: { _ in })
                }
            }
            .task {
                guard let request, request.card != nil || request.pin != nil || request.discoverCard, let store, store.serverJoins[request.id] == nil else { return }
                unavailable = store.openServerJoin(request) == nil
            }
            .onDisappear { if let request { store?.closeServerJoin(request) } }
        }

        /// The backend gave no model (it can't read this server's card here).
        static let unavailableState = ServerJoinState.error(.init(code: .hostNotFound, recoveryAction: .dismiss))
    }

    private struct PlainServerJoinView: View {
        let request: ServerJoinRequest
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @JoinDismiss private var dismiss
        @State private var saving = false
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Join server").font(.title2.bold())
                Text(request.server).textSelection(.enabled)
                if let instance = store.activeInstance {
                    Text("Add to \(instance.name) and join with Minecraft \(instance.gameVersion).")
                    Button(saving ? "Adding…" : "Add + Join") {
                        saving = true
                        Task {
                            if let server = await store.addServer(address: request.server, to: instance.id) {
                                nav.afterServerSheet = { store.play(instance.id, server: server); nav.showingLaunch = true }
                                dismiss()
                            }
                            saving = false
                        }
                    }.buttonStyle(.borderedProminent).disabled(saving)
                    if let error = store.lastError { Text(error).foregroundStyle(.red) }
                } else { Text("Create an instance first to join this server.") }
                Button("Cancel") { dismiss() }
            }.padding(24).background(Color.cofre.page)
        }
    }

    /// Observes the model: reading `server` and `state` here is what re-renders the sheet.
    private struct JoinSheetModelView: View {
        let model: any ServerJoinViewModel, card: Bool
        var body: some View { JoinSheetFrame(server: model.server, state: model.state, card: card) { model.send($0) } }
    }

    /// Header, scrolling body, pinned footer, and the adaptive presentation around them.
    struct JoinSheetFrame: View {
        let server: ServerSummary, state: ServerJoinState, card: Bool, send: (ServerJoinAction) -> Void

        @JoinDismiss private var dismiss
        @Environment(\.joinCard) private var cardContext
        private let theme = CofreTheme.standard
        @Environment(\.dynamicTypeSize) private var typeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var headerHeight: CGFloat = 76
        @State private var bodyHeight: CGFloat = 320
        @State private var footerHeight: CGFloat = 90
        @State private var sheetHeight: CGFloat = 0
        @State private var iconURL: URL?
        // Here, not in the bodies, so switching to the scrolling branch keeps them.
        @State private var showsAllMods = false
        @State private var showsAllChanges = false
        @State private var lastStageAnnouncement = Date.distantPast

        private var compact: Bool { !card }
        private var pad: CGFloat { compact ? theme.space.s7 : theme.space.s9 }

        var body: some View {
            VStack(spacing: 0) {
                JoinHeader(server: server, state: state, iconURL: iconURL ?? state.requirements?.iconURL)
                    .padding(.horizontal, pad).padding(.top, compact ? 22 : 24).padding(.bottom, 14)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        headerHeight = $0
                    }
                // A plain stack while everything fits; a scroll view between header and footer when the window is too short.
                if fits {
                    // Its full height, never squeezed, so the measurement that sizes the sheet stays true.
                    bodyStack.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    ScrollView { bodyStack }.scrollBounceBehavior(.basedOnSize)
                }
                if !typeSize.isAccessibilitySize {
                    footer
                        .padding(.horizontal, pad).padding(.top, 14).padding(.bottom, compact ? 12 : 24)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            footerHeight = $0
                        }
                }
            }
            .frame(maxWidth: compact ? .infinity : theme.space.card)
            // Bottom sheet: fills its detent. Card: as tall as the content, up to what the window allows.
            .frame(height: compact ? nil : min(fittedHeight, cardContext?.maxHeight ?? .infinity), alignment: .top)
            .frame(maxHeight: compact ? .infinity : nil, alignment: .top)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                sheetHeight = $0
            }
            .animation(reduceMotion ? nil : .easeOut(duration: theme.motion.column), value: compact ? 0 : fittedHeight)
            .background(Color.cofre.page)
            .environment(\.widthClass, compact ? .compact : .medium)
            .environment(\.isPushed, false)
            .presentationBackground(Color.cofre.page)
            .presentationDragIndicator(compact ? .visible : .hidden)
            .presentationDetents(compact ? [.height(fittedHeight)] : [.large])
            .background {
                // Esc closes from anywhere, even with nothing focused.
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of: state.requirements?.iconURL) { _, url in if let url { iconURL = url } }
            .onChange(of: state.phase) { _, _ in announce() }
            .onChange(of: state.warnings?.openBlockers.count) { old, new in
                if let old, let new, new < old {
                    post(
                        new == 0
                            ? String(localized: "Everything's ready. You can install.")
                            : String(localized: "\(new) left"))
                }
            }
            .onChange(of: state.installing?.currentStageIndex) { _, _ in announceStage() }
            .sensoryFeedback(.success, trigger: state.phase) { _, new in new == .ready }
        }

        /// Header + body + footer, so the compact detent hugs the content. Taller content scrolls between them.
        private var fittedHeight: CGFloat {
            headerHeight + bodyHeight + (typeSize.isAccessibilitySize ? 0 : footerHeight)
        }
        private var fits: Bool {
            let room = compact ? sheetHeight : (cardContext?.maxHeight ?? .infinity)
            return room == 0 || fittedHeight <= room + 1
        }

        private var bodyStack: some View {
            VStack(alignment: .leading, spacing: 14) {
                stateBody
                // Accessibility sizes: the footer scrolls with the content, so the body keeps room.
                if typeSize.isAccessibilitySize { footer.padding(.top, 4) }
            }
            .padding(.horizontal, pad).padding(.bottom, typeSize.isAccessibilitySize ? 16 : 2)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                bodyHeight = $0
            }
        }

        @ViewBuilder private var stateBody: some View {
            switch state {
            case .resolving: JoinResolvingBody()
            case .requirements(let r): JoinRequirementsBody(req: r, showsMods: $showsAllMods, send: send)
            case .warnings(let w, let r): JoinWarningsBody(warnings: w, req: r, send: send)
            case .installing(let s): JoinInstallingBody(state: s)
            case .updateAvailable(let u): JoinUpdateBody(update: u, showsAll: $showsAllChanges)
            case .error(let e): JoinErrorBody(error: e)
            case .ready(let r): JoinReadyBody(ready: r, send: send)
            }
        }

        @ViewBuilder private var footer: some View {
            switch state {
            case .resolving: EmptyView()
            case .requirements(let r): JoinRequirementsFooter(req: r, send: send)
            case .warnings(let w, let r): JoinWarningsFooter(warnings: w, req: r, send: send)
            case .installing(let s): JoinInstallingFooter(state: s, send: send)
            case .updateAvailable(let u): JoinUpdateFooter(update: u, send: send)
            case .error(let e): JoinErrorFooter(error: e, send: send)
            case .ready(let r): JoinReadyFooter(ready: r, send: send)
            }
        }

        // VoiceOver hears each state change; install steps at most every 2 s (§2 #13).
        private func announce() {
            let text: String? =
                switch state {
                case .resolving: String(localized: "Checking \(server.name)")
                case .requirements(let r): String(localized: "Ready to install, \(r.formattedDownloadSize)")
                case .warnings(let w, _):
                    w.openBlockers.isEmpty
                        ? String(localized: "Check these before you join")
                        : String(localized: "\(w.openBlockers.count) things need you before you join")
                case .installing: String(localized: "Installing")
                case .updateAvailable: String(localized: "The server updated its pack")
                case .error: nil  // The danger banner announces itself.
                case .ready: String(localized: "Ready to join")
                }
            if let text { post(text) }
        }

        private func announceStage() {
            guard let s = state.installing, s.stages.indices.contains(s.currentStageIndex),
                Date.now.timeIntervalSince(lastStageAnnouncement) >= 2
            else { return }
            lastStageAnnouncement = .now
            post(
                String(
                    localized:
                        "Step \(s.currentStageIndex + 1) of \(s.stages.count), \(s.stages[s.currentStageIndex].title)"))
        }

        private func post(_ text: String) { AccessibilityNotification.Announcement(text).post() }
    }

    // MARK: - Card (regular width)

    /// Regular width: the sheet as a centered card over a dimmed window, up to 560 pt wide and as tall as its content.
    /// An overlay rather than a system sheet, because iPad sheets size themselves once and can't follow the content
    /// as the state changes. Modal for VoiceOver; Esc, the scrub gesture and a tap outside close it.
    public struct JoinServerCard: View {
        let request: ServerJoinRequest
        let onClose: () -> Void
        private let theme = CofreTheme.standard

        public init(request: ServerJoinRequest, onClose: @escaping () -> Void) {
            self.request = request
            self.onClose = onClose
        }

        public var body: some View {
            GeometryReader { g in
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture(perform: onClose)
                        .accessibilityHidden(true)
                    JoinServerSheet(request: request, style: .card)
                        // Block recipe (§1.4): bevel on top, 2 pt outline, square.
                        .overlay(alignment: .top) {
                            Color.cofre.bevel.frame(height: theme.block.bevel).padding(
                                [.horizontal, .top], theme.block.outline)
                        }
                        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: theme.block.outline) }
                        .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
                        .environment(
                            \.joinCard, JoinCardContext(close: onClose, maxHeight: max(200, g.size.height - 48))
                        )
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape, onClose)
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .onAppear { AccessibilityNotification.ScreenChanged().post() }
        }
    }

    /// What the card overlay hands the sheet: how to close it, and the most height it may take.
    struct JoinCardContext {
        var close: () -> Void
        var maxHeight: CGFloat
    }

    extension EnvironmentValues {
        @Entry var joinCard: JoinCardContext? = nil
    }

    /// Closes the Join server sheet: the card overlay's close, or the system sheet's dismiss.
    @propertyWrapper struct JoinDismiss: DynamicProperty {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.joinCard) private var card
        var wrappedValue: () -> Void { card?.close ?? { dismiss() } }
    }

    // MARK: - Header

    struct JoinHeader: View {
        let server: ServerSummary, state: ServerJoinState, iconURL: URL?
        @JoinDismiss private var dismiss

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                ServerIcon(url: iconURL, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: server.name).cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    status.cofreFont(.code).foregroundStyle(Color.cofre.muted).fixedSize(
                        horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    dismiss()
                } label: {
                    Text(verbatim: "✕").foregroundStyle(Color.cofre.muted)
                }
                .buttonStyle(.block(.secondary, size: .small, fullWidth: false))
                .accessibilityLabel(state.phase == .installing ? Text("Hide. Setup keeps going.") : Text("Close"))
            }
        }

        @ViewBuilder private var status: some View {
            switch state {
            case .resolving: Text(verbatim: server.address)
            case .installing(let s): Text(verbatim: s.title)
            case .updateAvailable(let u):
                Text("Pack \(Self.version(u.currentVersion)) → ")
                    + Text(verbatim: Self.version(u.newVersion)).foregroundStyle(Color.cofre.accent)
            default:
                let line = [server.detail, server.pingMS.map { "\($0) ms" }].compactMap { $0 }.joined(separator: " · ")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if server.pingMS != nil {
                        Rectangle().fill(Color.cofre.success).frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    Text(verbatim: line.isEmpty ? server.address : line)
                }
                .accessibilityElement(children: .combine)
            }
        }

        /// "2.4" → "v2.4"; leaves "v2.4" and "beta-3" alone.
        static func version(_ v: String) -> String { v.first?.isNumber == true ? "v\(v)" : v }
    }

    /// The server's favicon, or a grass block. Square, with the block outline.
    struct ServerIcon: View {
        let url: URL?, size: CGFloat
        var body: some View {
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.interpolation(.none).resizable()
                        } else {
                            PixelIcon(.grass, size: size)
                        }
                    }
                } else {
                    PixelIcon(.grass, size: size)
                }
            }
            .frame(width: size, height: size)
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Shared pieces

    /// The one primary action. Shows the download size, plus "1 left" while something blocks it.
    struct JoinPrimaryButton: View {
        let title: LocalizedStringKey
        var size: String?
        var status: String?
        var enabled = true
        let action: () -> Void

        var body: some View {
            let detail = [size, status].compactMap { $0 }.joined(separator: " · ")
            Button(action: action) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        name
                        trailing(detail)
                    }
                    VStack(spacing: 2) {
                        name
                        trailing(detail)
                    }.padding(.vertical, 6)
                }
            }
            .buttonStyle(.block(.primary, size: .large))
            .disabled(!enabled)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(detail.isEmpty ? Text(title) : Text(title) + Text(verbatim: ", \(detail)"))
        }

        private var name: some View {
            HStack(spacing: 8) {
                PixelIcon(.play, size: 16)
                Text(title)
            }
        }

        @ViewBuilder private func trailing(_ detail: String) -> some View {
            if !detail.isEmpty { Text(verbatim: detail).cofreFont(.code).opacity(0.85) }
        }
    }

    /// A short note: an inset well, or a tinted panel with a 4 pt bar for a tone (warn, accent, danger).
    struct JoinNote<Content: View>: View {
        let tone: Tone?, content: Content
        private let theme = CofreTheme.standard

        init(tone: Tone? = nil, @ViewBuilder content: () -> Content) {
            self.tone = tone
            self.content = content()
        }

        var body: some View {
            content
                .padding(.leading, tone == nil ? 12 : 14).padding(.trailing, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if let tone {
                        BlockBackground(.panel)
                            .overlay { Color.cofre.tint(tone, amount: 0.16).padding(theme.block.outline) }
                            .overlay(alignment: .leading) {
                                Color.cofre.tone(tone).frame(width: theme.block.selectionBar)
                                    .padding(.vertical, theme.block.outline).padding(.leading, theme.block.outline)
                            }
                    } else {
                        BlockBackground(.well)
                    }
                }
        }
    }

    /// Note text: Geist caption, wraps.
    struct NoteText: View {
        let text: Text
        var color = Color.cofre.inkSoft
        init(_ key: LocalizedStringKey, color: Color = Color.cofre.inkSoft) {
            text = Text(key)
            self.color = color
        }
        init(verbatim: String, color: Color = Color.cofre.inkSoft) {
            text = Text(verbatim: verbatim)
            self.color = color
        }
        var body: some View {
            text.cofreFont(.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "~25 s", "~2 min".
    func joinDuration(_ seconds: Int) -> String {
        seconds < 60 ? "~\(max(1, seconds)) s" : "~\(Int((Double(seconds) / 60).rounded())) min"
    }

    /// "↗" as text, not the emoji the system font would pick.
    let joinArrow = "\u{2197}\u{FE0E}"

    /// "iPhone" or "iPad", for copy like "Won't work on iPhone". Never used for layout.
    @MainActor var joinDeviceName: String { UIDevice.current.model }

    // MARK: - State helpers

    extension ServerJoinState {
        /// The state without payloads, for announcements and haptics.
        enum Phase: Equatable { case resolving, requirements, warnings, installing, update, error, ready }

        var phase: Phase {
            switch self {
            case .resolving: .resolving
            case .requirements: .requirements
            case .warnings: .warnings
            case .installing: .installing
            case .updateAvailable: .update
            case .error: .error
            case .ready: .ready
            }
        }

        var requirements: ServerJoinRequirementsState? {
            switch self {
            case .requirements(let r), .warnings(_, let r): r
            default: nil
            }
        }
        var warnings: ServerJoinWarningState? { if case .warnings(let w, _) = self { w } else { nil } }
        var installing: ServerJoinInstallingState? { if case .installing(let s) = self { s } else { nil } }
    }

    extension ServerJoinWarningState {
        /// Blocking and security items not resolved yet.
        var openBlockers: [WarningItem] {
            warnings.filter { !$0.isResolved && ($0.severity == .blocking || $0.severity == .security) }
        }
        /// Security items always block; `canProceedAnyway` only waives blocking ones.
        var canInstall: Bool { openBlockers.allSatisfy { $0.severity == .blocking && canProceedAnyway } }
        /// Something open can't be fixed from this sheet (no action), so only the server owner can unblock it.
        var isStuck: Bool { !canInstall && openBlockers.contains { $0.actionLabel == nil && $0.actionURL == nil } }
        /// The primary button's status: `nil` when it can install, "Blocked" when stuck, else "1 left".
        var primaryStatus: String? {
            canInstall ? nil : isStuck ? String(localized: "Blocked") : String(localized: "\(openBlockers.count) left")
        }
    }
#endif
