import Foundation

/// A project's full page (About, Gallery, links), the same shape for every provider. The header's numbers come from
/// the search hit; this adds what only the project request has.
public struct ProjectPage: Sendable, Hashable {
    /// Modrinth sends Markdown (with raw HTML inside); CurseForge sends HTML. `PageDocument` turns both into one page.
    public enum Body: Sendable, Hashable {
        case markdown(String)
        case html(String)
    }
    public struct Image: Sendable, Hashable, Identifiable {
        public let id: String
        /// `thumb` is small enough for the grid; `full` is only for the viewer.
        public let thumb: URL, full: URL
        public let title: String?, caption: String?
        public let featured: Bool
        public init(
            id: String, thumb: URL, full: URL? = nil, title: String? = nil, caption: String? = nil,
            featured: Bool = false
        ) {
            self.id = id
            self.thumb = thumb
            self.full = full ?? thumb
            self.title = title
            self.caption = caption
            self.featured = featured
        }
    }
    /// A YouTube video found in the body. It always opens in YouTube, never inline.
    public struct Video: Sendable, Hashable, Identifiable {
        public let id: String
        public var watch: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
        public var thumb: URL { URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")! }
        /// Only real YouTube IDs, so the URLs above are always valid.
        public init?(youTubeID id: String) {
            guard (6...32).contains(id.count),
                id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            else { return nil }
            self.id = id
        }
    }
    public struct Link: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case website, source, issues, wiki, discord
            case donate(String)
        }
        public let kind: Kind, url: URL
        public init(kind: Kind, url: URL) {
            self.kind = kind
            self.url = url
        }
    }

    public let id: String, source: ProjectSource
    public let title: String, summary: String, iconURL: URL?
    public let body: Body?
    /// Featured first, then the provider's order.
    public let gallery: [Image]
    /// Filled from the body by `PageDocument`; providers have no video field.
    public var videos: [Video]
    public let links: [Link]
    public let license: String?
    public init(
        id: String, source: ProjectSource, title: String, summary: String = "", iconURL: URL? = nil, body: Body? = nil,
        gallery: [Image] = [], videos: [Video] = [], links: [Link] = [], license: String? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.summary = summary
        self.iconURL = iconURL
        self.body = body
        self.gallery = gallery
        self.videos = videos
        self.links = links
        self.license = license
    }
}

extension Modrinth {
    /// `GET /project/{id}`, limited to the page's fields.
    struct ProjectDetail: Decodable {
        struct License: Decodable {
            let id: String
            let name: String?
        }
        struct Donation: Decodable {
            let platform: String?
            let url: String
        }
        struct Shot: Decodable {
            let url: String
            /// Not in the OpenAPI spec but sent live; the thumbnail stands in when it's missing.
            let rawURL: String?
            let featured: Bool
            let title: String?
            let description: String?
            let ordering: Int?
            enum CodingKeys: String, CodingKey {
                case url
                case rawURL = "raw_url"
                case featured, title, description, ordering
            }
        }
        let id: String
        let title: String
        let description: String?
        let body: String?
        let icon: String?
        let license: License?
        let sourceURL: String?
        let issuesURL: String?
        let wikiURL: String?
        let discordURL: String?
        let donations: [Donation]?
        let gallery: [Shot]?
        enum CodingKeys: String, CodingKey {
            case id, title, description, body
            case icon = "icon_url"
            case license
            case sourceURL = "source_url"
            case issuesURL = "issues_url"
            case wikiURL = "wiki_url"
            case discordURL = "discord_url"
            case donations = "donation_urls"
            case gallery
        }
    }
}

extension ProjectPage {
    init(modrinth p: Modrinth.ProjectDetail) {
        func text(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        // Featured first, then `ordering`; ties keep Modrinth's own order.
        let shots = (p.gallery ?? []).enumerated().sorted {
            ($0.element.featured ? 0 : 1, $0.element.ordering ?? 0, $0.offset)
                < ($1.element.featured ? 0 : 1, $1.element.ordering ?? 0, $1.offset)
        }
        let gallery = shots.map(\.element).compactMap { shot in
            Modrinth.url(shot.url).map {
                Image(
                    id: shot.url, thumb: $0, full: Modrinth.url(shot.rawURL), title: text(shot.title),
                    caption: text(shot.description), featured: shot.featured)
            }
        }
        let fixed: [(Link.Kind, String?)] = [
            (.source, p.sourceURL), (.issues, p.issuesURL), (.wiki, p.wikiURL), (.discord, p.discordURL),
        ]
        // User content opened outside the app: web links only.
        let links = (fixed + (p.donations ?? []).map { (.donate($0.platform ?? ""), $0.url) }).compactMap { kind, url in
            Modrinth.url(url).flatMap {
                ["http", "https"].contains($0.scheme?.lowercased()) ? Link(kind: kind, url: $0) : nil
            }
        }
        // Custom licenses come with an empty name and an ID like "LicenseRef-Create-Mod-License".
        let license = p.license.map { license in
            text(license.name)
                ?? license.id.replacingOccurrences(of: "LicenseRef-", with: "").replacingOccurrences(of: "-", with: " ")
        }
        self.init(
            id: p.id, source: .modrinth, title: p.title, summary: p.description ?? "", iconURL: Modrinth.url(p.icon),
            body: text(p.body).map(Body.markdown), gallery: gallery, videos: [], links: links, license: license)
    }
}
