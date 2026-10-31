import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// A project body (Modrinth Markdown or CurseForge HTML) as one self-contained HTML page for a locked-down web view.
///
/// The body passes an allowlist: unknown tags lose their markup but keep their text, scripts, styles, forms,
/// embeds and their contents disappear, links keep only `http(s)` targets and images only `https`/`data:` ones.
/// YouTube iframes become linked thumbnail cards (videos never play inline) and land in `videos`.
/// The page also carries a strict CSP, so anything that slips past the allowlist still can't load or run.
public struct PageDocument: Sendable, Equatable {
    /// Fonts are embedded as `data:` URLs because the page may load nothing from the network or the bundle.
    public struct Font: Sendable, Equatable {
        public enum Family: String, Sendable {
            case body = "Geist"
            case heading = "Pixelify Sans"
            case code = "Geist Mono"
        }
        public let family: Family
        public let weight: Int
        public let data: Data
        public init(family: Family, weight: Int, data: Data) {
            self.family = family
            self.weight = weight
            self.data = data
        }
    }

    /// CSS colour values; CofreUI fills them from its tokens.
    public struct Colors: Sendable, Equatable {
        public let page: String, ink: String, muted: String, accent: String, well: String, line: String
        public init(page: String, ink: String, muted: String, accent: String, well: String, line: String) {
            self.page = page
            self.ink = ink
            self.muted = muted
            self.accent = accent
            self.well = well
            self.line = line
        }
    }

    public struct Style: Sendable, Equatable {
        public let colors: Colors
        public let fonts: [Font]
        public init(colors: Colors, fonts: [Font]) {
            self.colors = colors
            self.fonts = fonts
        }
    }

    public let html: String
    /// In body order, without repeats.
    public let videos: [ProjectPage.Video]

    public init(_ body: ProjectPage.Body, style: Style) {
        let clean: (html: String, videos: [ProjectPage.Video])
        switch body {
        case .markdown(let markdown): clean = Self.sanitize(Self.html(fromMarkdown: markdown))
        case .html(let html): clean = Self.sanitize(html)
        }
        html = Self.page(body: clean.html, style: style)
        videos = clean.videos
    }

    public static let contentSecurityPolicy =
        "default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'"

    // MARK: Markdown

    /// GitHub-flavoured Markdown with raw HTML kept (Modrinth bodies mix both); `sanitize` makes it safe.
    static func html(fromMarkdown markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_UNSAFE) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let root = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(root) }
        guard let html = cmark_render_html(root, CMARK_OPT_UNSAFE, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(html) }
        return String(cString: html)
    }

    // MARK: Sanitizing

    private static let allowedTags: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "blockquote", "br", "caption", "center", "cite", "code", "col", "colgroup",
        "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5",
        "h6", "hr", "i", "img", "ins", "kbd", "li", "mark", "ol", "p", "pre", "q", "rp", "rt", "ruby", "s", "samp",
        "small", "span", "strike", "strong", "sub", "summary", "sup", "table", "tbody", "td", "tfoot", "th", "thead",
        "time", "tr", "tt", "u", "ul", "var", "wbr",
    ]
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "frame", "hr", "img", "input", "keygen", "link", "meta", "param",
        "source",
        "track", "wbr",
    ]
    /// Their content is raw text up to the matching end tag, so it's skipped without being parsed.
    private static let rawTextTags: Set<String> = [
        "script", "style", "iframe", "textarea", "title", "xmp", "noembed", "noframes", "plaintext",
    ]
    /// Dropped with everything inside them.
    private static let droppedContainers: Set<String> = [
        "object", "applet", "form", "select", "svg", "math", "template", "video", "audio", "canvas", "frameset",
    ]
    private static let globalAttributes: Set<String> = ["title", "align", "style", "dir"]
    private static let tagAttributes: [String: Set<String>] = [
        "a": ["href"], "img": ["src", "alt", "width", "height"], "td": ["colspan", "rowspan"],
        "th": ["colspan", "rowspan"], "ol": ["start"], "li": ["value"], "details": ["open"], "col": ["span"],
        "colgroup": ["span"],
    ]

    struct Tag {
        var name: String
        var isEnd: Bool
        var attributes: [(name: String, value: String)]
        var end: Int
        func value(_ name: String) -> String? { attributes.first { $0.name == name }?.value }
    }

    static func sanitize(_ html: String) -> (html: String, videos: [ProjectPage.Video]) {
        let bytes = Array(html.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var videos: [ProjectPage.Video] = []
        var skipping: (name: String, depth: Int)?
        var i = 0
        while i < bytes.count {
            guard bytes[i] == UInt8(ascii: "<") else {
                let next = bytes[i...].firstIndex(of: UInt8(ascii: "<")) ?? bytes.count
                if skipping == nil { out += bytes[i..<next] }
                i = next
                continue
            }
            if bytes[i...].starts(with: "<!--".utf8) {
                i = find(Array("-->".utf8), in: bytes, from: i + 4).map { $0 + 3 } ?? bytes.count
                continue
            }
            if i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "!") || bytes[i + 1] == UInt8(ascii: "?") {
                i = (bytes[i...].firstIndex(of: UInt8(ascii: ">")) ?? bytes.count - 1) + 1
                continue
            }
            guard let tag = parseTag(bytes, at: i) else {
                if skipping == nil { out += Array("&lt;".utf8) }
                i += 1
                continue
            }
            i = tag.end
            if !tag.isEnd, rawTextTags.contains(tag.name) {
                let close = find(Array("</\(tag.name)".utf8), in: bytes, from: i, caseInsensitive: true)
                if tag.name == "iframe", skipping == nil {
                    if let video = tag.value("src").flatMap(youTubeID).flatMap(ProjectPage.Video.init(youTubeID:)) {
                        if !videos.contains(video) { videos.append(video) }
                        out += Array(videoCard(video).utf8)
                    }
                    // `<iframe … />` with no end tag is common in Markdown; keep what follows it.
                    guard close != nil else { continue }
                }
                i = close.flatMap { c in bytes[c...].firstIndex(of: UInt8(ascii: ">")).map { $0 + 1 } } ?? bytes.count
                continue
            }
            if let skip = skipping {
                if tag.name == skip.name {
                    let depth = skip.depth + (tag.isEnd ? -1 : 1)
                    skipping = depth == 0 ? nil : (skip.name, depth)
                }
                continue
            }
            if tag.isEnd {
                if allowedTags.contains(tag.name), !voidTags.contains(tag.name) { out += Array("</\(tag.name)>".utf8) }
                continue
            }
            if droppedContainers.contains(tag.name) {
                if !voidTags.contains(tag.name) { skipping = (tag.name, 1) }
                continue
            }
            // GFM task lists render disabled checkboxes; inputs are dropped, so keep the state as a glyph.
            if tag.name == "input", tag.value("type")?.lowercased() == "checkbox" {
                out += Array((tag.value("checked") != nil ? "☑" : "☐").utf8)
                continue
            }
            guard allowedTags.contains(tag.name), let clean = cleanTag(tag) else { continue }
            out += Array(clean.utf8)
        }
        return (String(decoding: out, as: UTF8.self), videos)
    }

    /// The allowed attributes, re-escaped. Nil when the tag is useless without a dropped attribute (an image).
    private static func cleanTag(_ tag: Tag) -> String? {
        var result = "<\(tag.name)"
        let allowed = globalAttributes.union(tagAttributes[tag.name] ?? [])
        var seen = Set<String>()
        var hasSource = false
        for (name, raw) in tag.attributes where allowed.contains(name) && seen.insert(name).inserted {
            let value: String?
            switch name {
            case "href": value = linkURL(raw)
            case "src": value = imageURL(raw)
            case "style": value = safeStyle(raw)
            case "width", "height", "colspan", "rowspan", "start", "value", "span":
                value = raw.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "%") } && !raw.isEmpty ? raw : nil
            case "open": value = ""
            default: value = raw
            }
            guard let value else { continue }
            hasSource = hasSource || name == "src"
            result += value.isEmpty && name == "open" ? " open" : " \(name)=\"\(escape(value))\""
        }
        if tag.name == "img", !hasSource { return nil }
        return result + ">"
    }

    static func linkURL(_ raw: String) -> String? {
        let url = absolute(raw)
        let lower = url.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://") ? url : nil
    }

    static func imageURL(_ raw: String) -> String? {
        let url = absolute(raw)
        let lower = url.lowercased()
        if lower.hasPrefix("https://") { return url }
        let images = ["png", "jpeg", "jpg", "gif", "webp"]
        return images.contains { lower.hasPrefix("data:image/\($0);base64,") } ? url : nil
    }

    private static func absolute(_ raw: String) -> String {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.hasPrefix("//") ? "https:" + url : url
    }

    /// Inline styles may lay out and colour, never load anything or escape their box.
    private static func safeStyle(_ raw: String) -> String? {
        let lower = raw.lowercased()
        let banned = [
            "url(", "image-set(", "expression", "@import", "\\", "javascript:", "behavior", "binding", "position",
        ]
        return banned.contains { lower.contains($0) } ? nil : raw
    }

    static func youTubeID(_ raw: String) -> String? {
        guard let parts = URLComponents(string: absolute(raw)), let host = parts.host?.lowercased() else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        let candidate: String?
        switch host {
        case "youtu.be", "www.youtu.be": candidate = path.first
        case "youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com":
            if path.first == "watch" {
                candidate = parts.queryItems?.first { $0.name == "v" }?.value
            } else if path.count >= 2, ["embed", "v", "shorts", "live"].contains(path[0]) {
                candidate = path[1]
            } else {
                candidate = nil
            }
        default: candidate = nil
        }
        guard let id = candidate, id.count == 11, id != "videoseries",
            id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return id
    }

    private static func videoCard(_ video: ProjectPage.Video) -> String {
        "<a class=\"video\" href=\"\(video.watch)\"><img src=\"\(video.thumb)\" alt=\"Play video on YouTube\"></a>"
    }

    /// Parses `<name attr=value …>` or `</name>` at `start`. Nil when it isn't a tag, which HTML treats as text.
    static func parseTag(_ b: [UInt8], at start: Int) -> Tag? {
        var i = start + 1
        let isEnd = i < b.count && b[i] == UInt8(ascii: "/")
        if isEnd { i += 1 }
        guard i < b.count, isLetter(b[i]) else { return nil }
        let nameStart = i
        while i < b.count, isLetter(b[i]) || isDigit(b[i]) || b[i] == UInt8(ascii: "-") || b[i] == UInt8(ascii: ":") {
            i += 1
        }
        var tag = Tag(
            name: String(decoding: b[nameStart..<i], as: UTF8.self).lowercased(), isEnd: isEnd, attributes: [], end: 0)
        while i < b.count {
            while i < b.count, isSpace(b[i]) || b[i] == UInt8(ascii: "/") { i += 1 }
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: ">") {
                tag.end = i + 1
                return tag
            }
            let attrStart = i
            i += 1
            while i < b.count, !isSpace(b[i]), b[i] != UInt8(ascii: "/"), b[i] != UInt8(ascii: ">"),
                b[i] != UInt8(ascii: "=")
            {
                i += 1
            }
            let name = String(decoding: b[attrStart..<i], as: UTF8.self).lowercased()
            while i < b.count, isSpace(b[i]) { i += 1 }
            var value = ""
            if i < b.count, b[i] == UInt8(ascii: "=") {
                i += 1
                while i < b.count, isSpace(b[i]) { i += 1 }
                guard i < b.count else { return nil }
                let quote = b[i]
                if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                    guard let close = b[(i + 1)...].firstIndex(of: quote) else { return nil }
                    value = String(decoding: b[(i + 1)..<close], as: UTF8.self)
                    i = close + 1
                } else {
                    let valueStart = i
                    while i < b.count, !isSpace(b[i]), b[i] != UInt8(ascii: ">") { i += 1 }
                    value = String(decoding: b[valueStart..<i], as: UTF8.self)
                }
            }
            tag.attributes.append((name, decodeEntities(value)))
        }
        return nil
    }

    /// Enough of HTML's character references for URL checks; unknown named ones stay as written.
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{a0}"]
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[rest.index(after: amp)...]
            let body = rest.prefix { $0.isLetter || $0.isNumber || $0 == "#" }
            var decoded: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                decoded = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if body.hasPrefix("#") {
                decoded = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = named[String(body)]
            }
            guard let decoded else {
                out += "&"
                continue
            }
            out += decoded
            rest = rest.dropFirst(body.count)
            if rest.first == ";" { rest = rest.dropFirst() }
        }
        return out + rest
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func find(_ needle: [UInt8], in b: [UInt8], from start: Int, caseInsensitive: Bool = false) -> Int? {
        guard needle.count <= b.count, start <= b.count - needle.count else { return nil }
        for i in start...(b.count - needle.count) {
            var match = true
            for (j, n) in needle.enumerated() where (caseInsensitive ? lower(b[i + j]) : b[i + j]) != n {
                match = false
                break
            }
            if match { return i }
        }
        return nil
    }

    private static func lower(_ c: UInt8) -> UInt8 { c >= 65 && c <= 90 ? c + 32 : c }
    private static func isLetter(_ c: UInt8) -> Bool { (c | 0x20) >= 97 && (c | 0x20) <= 122 }
    private static func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }
    private static func isSpace(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 10 || c == 12 || c == 13 }

    // MARK: Template

    private static func page(body: String, style: Style) -> String {
        let faces = style.fonts.map {
            "@font-face{font-family:\"\($0.family.rawValue)\";font-weight:\($0.weight);"
                + "src:url(data:font/ttf;base64,\($0.data.base64EncodedString())) format(\"truetype\")}"
        }
        let c = style.colors
        return """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
            <meta name="referrer" content="no-referrer">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            \(faces.joined(separator: "\n"))
            :root{color-scheme:dark;--page:\(c.page);--ink:\(c.ink);--muted:\(c.muted);--accent:\(c.accent);\
            --well:\(c.well);--line:\(c.line)}
            html{-webkit-text-size-adjust:100%}
            body{margin:0;font:-apple-system-body;font-family:"Geist",-apple-system,sans-serif;line-height:1.55;\
            color:var(--ink);background:var(--page);overflow-wrap:anywhere}
            h1,h2,h3,h4,h5,h6{font-family:"Pixelify Sans",-apple-system,sans-serif;font-weight:600;line-height:1.25;\
            margin:1.3em 0 .5em}
            h1{font-size:1.6em}h2{font-size:1.35em}h3{font-size:1.15em}h4,h5,h6{font-size:1em}
            p,ul,ol,dl,pre,table,blockquote,details,figure{margin:0 0 .9em}
            a{color:var(--accent);text-decoration:none}
            img{max-width:100%;height:auto}
            pre,code,kbd,samp,tt{font-family:"Geist Mono",ui-monospace,monospace;font-size:.88em}
            code,kbd{background:var(--well);border-radius:4px;padding:.1em .3em}
            pre{background:var(--well);border-radius:8px;padding:.8em;overflow-x:auto}
            pre code{background:none;padding:0}
            blockquote{padding:0 1em;border-left:3px solid var(--line);color:var(--muted);margin-left:0}
            table{border-collapse:collapse;display:block;max-width:100%;overflow-x:auto}
            th,td{border:1px solid var(--line);padding:.4em .6em}
            hr{border:0;border-top:1px solid var(--line);margin:1.4em 0}
            summary{color:var(--accent)}
            .video{display:block;position:relative;max-width:480px;aspect-ratio:16/9;border-radius:10px;\
            overflow:hidden;background:var(--well)}
            .video img{display:block;width:100%;height:100%;object-fit:cover}
            .video::after{content:"";position:absolute;inset:0;margin:auto;width:0;height:0;\
            border-style:solid;border-width:18px 0 18px 30px;border-color:transparent transparent transparent #fff;\
            filter:drop-shadow(0 0 10px rgba(0,0,0,.8))}
            </style></head><body>
            \(body)
            </body></html>
            """
    }
}
