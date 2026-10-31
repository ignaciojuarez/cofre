import XCTest

@testable import CofreKit

final class PageDocumentTests: XCTestCase {
    private let style = PageDocument.Style(
        colors: .init(page: "#000", ink: "#fff", muted: "#999", accent: "#a8f", well: "#111", line: "#333"),
        fonts: [.init(family: .body, weight: 400, data: Data("font".utf8))])

    func testCreateBodyKeepsOneVideoAndNoActiveContent() throws {
        let hostile =
            "\n<p onclick=\"x()\">Hi <img src=\"https://i.imgur.com/a.png\" onload='y()'></p>\n<script>z()</script>"
        let page = PageDocument(.markdown(try fixture("page-create.md") + hostile), style: style)
        XCTAssertEqual(page.videos.map(\.id), ["rR8W-f9YhYA"])
        XCTAssertEqual(page.videos.first?.watch.absoluteString, "https://www.youtube.com/watch?v=rR8W-f9YhYA")
        let html = page.html.lowercased()
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertNil(html.range(of: #"\son[a-z]+\s*="#, options: .regularExpression))
        XCTAssertTrue(
            page.html.contains(
                #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:;"#))
        XCTAssertTrue(page.html.contains(#"<a class="video" href="https://www.youtube.com/watch?v=rR8W-f9YhYA">"#))
        XCTAssertTrue(page.html.contains("<h2>Installation Requirements</h2>"))
        XCTAssertTrue(
            page.html.contains(
                #"<a href="https://neoforged.net/"><img src="https://i.imgur.com/90zvX3m.png" width="160">"#))
        XCTAssertTrue(page.html.contains(#"<p style="text-align: left;">"#))
        XCTAssertTrue(
            page.html.contains(
                "@font-face{font-family:\"Geist\";font-weight:400;src:url(data:font/ttf;base64,Zm9udA==)"))
    }

    func testCurseForgeHTMLDropsScriptFormAndOtherIframes() throws {
        let page = PageDocument(.html(try fixture("page-curseforge.html")), style: style)
        let body = try XCTUnwrap(page.html.components(separatedBy: "<body>").last)
        XCTAssertEqual(page.videos, [])
        for gone in [
            "<script", "document.cookie", "<form", "<input", "Log in", "vimeo", "<iframe", "<object", "<embed",
            "x.swf", "<style", "tracker.example", "onerror", "onclick", "onmouseover", "javascript", "alert",
            "insecure",
            "svg", "/relative\"",
        ] {
            XCTAssertFalse(body.contains(gone), gone)
        }
        XCTAssertTrue(body.contains(#"<a href="https://example.com/wiki">wiki</a>"#))
        XCTAssertTrue(body.contains(#"<a href="HTTPS://Example.com/Caps">Caps</a>"#))
        XCTAssertTrue(body.contains("<a>this</a>"))
        XCTAssertTrue(body.contains(#"<h2>About <span style="color: #e03e2d;">Example Mod</span></h2>"#))
        XCTAssertTrue(body.contains("<div>Styled</div>"))
        let images = body.matches(of: #/<img [^>]*>/#).map { String($0.output) }
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0.contains(#"src="https://media.forgecdn.net/"#) })
        XCTAssertTrue(images[0].contains(#"alt="Banner""#))
    }

    func testYouTubeIDsFromEveryEmbedForm() {
        let id = "rR8W-f9YhYA"
        for src in [
            "https://www.youtube.com/embed/\(id)?rel=0", "//www.youtube-nocookie.com/embed/\(id)",
            "https://youtu.be/\(id)", "https://m.youtube.com/watch?v=\(id)&t=3", "https://www.youtube.com/shorts/\(id)",
        ] {
            XCTAssertEqual(PageDocument.youTubeID(src), id, src)
        }
        for src in [
            "https://www.youtube.com/embed/videoseries?list=PL1", "https://evil.example/embed/\(id)",
            "https://www.youtube.com.evil.example/embed/\(id)", "https://www.youtube.com/embed/\(id)%22",
        ] {
            XCTAssertNil(PageDocument.youTubeID(src), src)
        }
    }

    func testRepeatedVideoListedOnceButCardedEachTime() {
        let iframe = #"<iframe src="https://www.youtube.com/embed/rR8W-f9YhYA"></iframe>"#
        let clean = PageDocument.sanitize(
            iframe + "<p>between</p>" + #"<IFRAME SRC="https://youtu.be/rR8W-f9YhYA" />after"#)
        XCTAssertEqual(clean.videos.count, 1)
        XCTAssertEqual(clean.html.components(separatedBy: #"class="video""#).count, 3)
        XCTAssertTrue(clean.html.hasSuffix("after"))
    }

    func testMarkdownEscapesCodeAndKeepsGFM() {
        let markdown = """
            Use `List<String>` and ~~old~~.

            ```java
            Map<String, Integer> m;
            ```

            | a | b |
            |---|---|
            | 1 | 2 |

            - [x] done
            - [ ] todo

            ![Shot](https://cdn.modrinth.com/s.png "Title") [link](javascript:alert(1)) https://modrinth.com
            """
        let html = PageDocument.sanitize(PageDocument.html(fromMarkdown: markdown)).html
        XCTAssertTrue(html.contains("<code>List&lt;String&gt;</code>"))
        XCTAssertTrue(html.contains("Map&lt;String, Integer&gt; m;"))
        XCTAssertTrue(html.contains("<del>old</del>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("☑ done") && html.contains("☐ todo"))
        XCTAssertTrue(html.contains(#"<img src="https://cdn.modrinth.com/s.png" alt="Shot" title="Title">"#))
        XCTAssertTrue(html.contains("<a>link</a>"))
        XCTAssertTrue(html.contains(#"<a href="https://modrinth.com">https://modrinth.com</a>"#))
    }

    func testMalformedMarkupCannotOpenATag() {
        for input in [
            "<img src=\"https://a.example/x.png\" alt=\"x\" onerror=\"y()", "a < b <-- c",
            "<a href='https://ok.example'",
            "<p title=\"&quot;><script>x()</script>\">t</p>", "<scr<script>ipt>alert(1)</script>",
            "<script>never closed", "<svg><script>x()</script></svg>after", "<!-- <script>x()</script> -->ok",
        ] {
            let html = PageDocument.sanitize(input).html
            XCTAssertFalse(html.lowercased().contains("<script"), input)
            XCTAssertNil(html.range(of: #"<[a-z]+[^>]*\son[a-z]+="#, options: .regularExpression), input)
        }
        XCTAssertEqual(PageDocument.sanitize("a < b").html, "a &lt; b")
        XCTAssertEqual(PageDocument.sanitize("<svg><script>x()</script></svg>after").html, "after")
        XCTAssertEqual(PageDocument.sanitize("<!-- c -->ok").html, "ok")
        XCTAssertEqual(
            PageDocument.sanitize("<p title=\"&quot;><b>\">t</p>").html, "<p title=\"&quot;&gt;&lt;b&gt;\">t</p>")
    }

    private func fixture(_ name: String) throws -> String {
        let parts = name.split(separator: ".")
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
