import Foundation

/// What a project page's web view does with a navigation. The page is user content, so it never navigates inside:
/// only Cofre's own load of the document is allowed, web links open outside, and every other scheme is dropped.
public enum PageLinkPolicy {
    public enum Decision: Sendable, Equatable {
        case allow
        case openOutside(URL)
        case cancel
    }

    /// `initialLoad` is true only for the document the app itself just loaded (`loadHTMLString`, so `about:blank`).
    public static func decide(_ url: URL?, initialLoad: Bool) -> Decision {
        guard let url else { return .cancel }
        if initialLoad, url.absoluteString == "about:blank" { return .allow }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else {
            return .cancel
        }
        return .openOutside(url)
    }
}
