#if canImport(UIKit)
    import CofreKit
    import SwiftUI
    import UIKit
    import WebKit

    /// A project's About (Modrinth Markdown or CurseForge HTML, already sanitized by `PageDocument`) in a locked-down
    /// web view: no page JavaScript, no cookies or storage, no link previews, and links never navigate inside it.
    /// It doesn't scroll on its own; its height follows the content, so it sits inside the page's scroll view.
    public struct ProjectBody: View {
        let document: PageDocument
        @State private var height: CGFloat = 1
        @Environment(\.dynamicTypeSize) private var typeSize

        public init(document: PageDocument) { self.document = document }

        public var body: some View {
            PageWebView(html: document.html, typeSize: typeSize, height: $height)
                .frame(height: height)
                .frame(maxWidth: .infinity)
        }
    }

    extension PageDocument.Style {
        /// Cofre's tokens as CSS, with the bundled fonts read once (Geist body, Pixelify headings, Geist Mono code).
        /// The page stays transparent so the screen's own background shows through.
        @MainActor static let cofre: PageDocument.Style = {
            let trait = UITraitCollection(
                accessibilityContrast: UIAccessibility.isDarkerSystemColorsEnabled ? .high : .normal)
            func css(_ color: PlatformColor) -> String {
                var r: CGFloat = 0
                var g: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                color.resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
                return "rgb(\(Int((r * 255).rounded())) \(Int((g * 255).rounded())) \(Int((b * 255).rounded())))"
            }
            let c = PlatformColor.cofre
            let faces: [(PageDocument.Font.Family, Int, String)] = [
                (.body, 400, Face.geist), (.body, 500, Face.geistMedium), (.body, 600, Face.geistSemi),
                (.heading, 600, Face.pixelSemi), (.code, 400, Face.mono),
            ]
            let fonts = faces.compactMap { family, weight, name in
                Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                    .flatMap { try? Data(contentsOf: $0) }
                    .map { PageDocument.Font(family: family, weight: weight, data: $0) }
            }
            return PageDocument.Style(
                colors: .init(
                    page: "transparent", ink: css(c.inkSoft), muted: css(c.muted), accent: css(c.accent),
                    well: css(c.well), line: css(c.bevel)),
                fonts: fonts)
        }()
    }

    private struct PageWebView: UIViewRepresentable {
        let html: String
        let typeSize: DynamicTypeSize
        @Binding var height: CGFloat

        func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

        func makeUIView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.defaultWebpagePreferences.allowsContentJavaScript = false
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            config.mediaTypesRequiringUserActionForPlayback = .all
            config.allowsInlineMediaPlayback = false
            config.allowsAirPlayForMediaPlayback = false
            config.allowsPictureInPictureMediaPlayback = false
            config.dataDetectorTypes = []
            let web = WKWebView(frame: .zero, configuration: config)
            web.navigationDelegate = context.coordinator
            web.allowsLinkPreview = false
            web.isOpaque = false
            web.backgroundColor = .clear
            web.scrollView.backgroundColor = .clear
            web.scrollView.isScrollEnabled = false
            web.scrollView.bounces = false
            web.scrollView.contentInsetAdjustmentBehavior = .never
            context.coordinator.observe(web)
            return web
        }

        func updateUIView(_ web: WKWebView, context: Context) {
            context.coordinator.height = $height
            context.coordinator.load(html, typeSize: typeSize, into: web)
        }

        @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
            var height: Binding<CGFloat>
            private var shown: (html: String, typeSize: DynamicTypeSize)?
            /// Set by our own `loadHTMLString`; the next main-frame load of it is the only navigation allowed.
            private var awaitingDocument = false
            private var observation: NSKeyValueObservation?

            init(height: Binding<CGFloat>) { self.height = height }

            /// Dynamic Type sizes `-apple-system-body` when the page loads, so a size change renders it again.
            func load(_ html: String, typeSize: DynamicTypeSize, into web: WKWebView) {
                guard shown?.html != html || shown?.typeSize != typeSize else { return }
                shown = (html, typeSize)
                awaitingDocument = true
                web.loadHTMLString(html, baseURL: nil)
            }

            func observe(_ web: WKWebView) {
                observation = web.scrollView.observe(\.contentSize) { [weak self, weak web] _, _ in
                    Task { @MainActor in if let web { self?.measure(web) } }
                }
            }

            /// `contentSize` never drops below the frame, so it can't shrink the view after a rotation or a smaller
            /// text size. The document's own height can; app scripts still run with page JavaScript off.
            private func measure(_ web: WKWebView) {
                let fallback = web.scrollView.contentSize.height
                web.evaluateJavaScript("document.body.scrollHeight", in: nil, in: .defaultClient) {
                    [weak self] result in
                    let measured = (try? result.get()).flatMap { $0 as? NSNumber }.map { CGFloat($0.doubleValue) }
                    let next = ceil(measured.flatMap { $0 > 0 ? $0 : nil } ?? fallback)
                    if let self, abs(self.height.wrappedValue - next) >= 1 { self.height.wrappedValue = next }
                }
            }

            func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy
            {
                let initial =
                    awaitingDocument && action.navigationType == .other && action.targetFrame?.isMainFrame == true
                switch PageLinkPolicy.decide(action.request.url, initialLoad: initial) {
                case .allow:
                    awaitingDocument = false
                    return .allow
                case .openOutside(let url):
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    return .cancel
                case .cancel:
                    return .cancel
                }
            }

            func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) { measure(web) }

            /// WebKit's content process can be killed in the background; render the page again.
            func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
                guard let html = shown?.html, let typeSize = shown?.typeSize else { return }
                shown = nil
                load(html, typeSize: typeSize, into: web)
            }
        }
    }

    #Preview("About") {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "Sodium").cofreFont(.title).foregroundStyle(Color.cofre.ink)
                if let body = ProjectPage.sample(id: "sodium").body {
                    ProjectBody(document: PageDocument(body, style: .cofre))
                }
            }
            .padding()
        }
        .background(Color.cofre.page)
    }
#endif
