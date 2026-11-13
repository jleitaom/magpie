import Foundation
import Testing
@testable import MagpieKit

struct LinksTests {
    @Test("Reads links from pasted text", arguments: [
        ("https://example.com/a", true), ("example.com/path?x=1", true), ("  https://youtu.be/abc \n", true),
        ("hello world", false), ("not a link", false), ("ftp://example.com", false), ("localhost", false), ("", false),
        // One word with a dot is a link only when it looks like a site.
        ("example.com", true), ("www.rtp.pt", true), ("magpie.app", true), ("example.museum/visit", true), ("example.museum?x=1", true),
        ("john@example.com", false), ("1.2.1", false), ("notes.txt", false), ("readme.md", false), ("Dr.Smith", false), ("e.g.", false),
        // With https:// in front, anything with a host is taken at its word.
        ("https://example.museum", true), ("https://notes.txt", true), ("http://192.168.1.1", true),
    ])
    func parse(text: String, isLink: Bool) {
        #expect((Links.parse(text) != nil) == isLink)
    }

    @Test("The same page normalizes to the same string", arguments: [
        ("https://www.Example.com/post/", "http://example.com/post"),
        ("https://example.com/post?utm_source=x&utm_medium=y", "https://example.com/post"),
        ("https://example.com/post#comments", "https://example.com/post"),
        ("https://example.com/?b=2&a=1", "https://example.com?a=1&b=2"),
        ("https://youtu.be/abc?si=tracking", "https://youtu.be/abc"),
    ])
    func sameAfterNormalizing(a: String, b: String) {
        #expect(Links.normalize(URL(string: a)!) == Links.normalize(URL(string: b)!))
    }

    @Test("A route after # is another page; an anchor isn't")
    func hashRoutes() {
        func same(_ a: String, _ b: String) -> Bool { Links.normalize(URL(string: a)!) == Links.normalize(URL(string: b)!) }
        #expect(!same("https://app.example.com/#/inbox", "https://app.example.com/#/archive"))
        #expect(!same("https://example.com/#!/photo/3", "https://example.com/#!/photo/4"))
        #expect(same("https://app.example.com/#/inbox", "http://www.app.example.com/#/inbox"))
        #expect(same("https://example.com/post#comments", "https://example.com/post#top"))
    }

    @Test func differentPagesStayDifferent() {
        #expect(Links.normalize(URL(string: "https://example.com/a")!) != Links.normalize(URL(string: "https://example.com/b")!))
        #expect(Links.normalize(URL(string: "https://example.com/watch?v=1")!) != Links.normalize(URL(string: "https://example.com/watch?v=2")!))
    }

    @Test("Guesses the kind from the URL", arguments: [
        ("https://www.youtube.com/watch?v=x", LinkKind.video), ("https://youtu.be/x", .video), ("https://vimeo.com/123", .video),
        ("https://maps.apple.com/?q=Lisbon", .place), ("https://www.google.com/maps/place/x", .place),
        ("https://example.com/photo.JPG", .image), ("https://discogs.com/release/1", .link),
    ])
    func kind(url: String, kind: LinkKind) {
        #expect(Links.kind(URL(string: url)!) == kind)
    }

    @Test func siteName() {
        #expect(Links.siteName(URL(string: "https://www.Discogs.com/release/1")!) == "discogs.com")
    }

    @Test func titles() {
        #expect(Titles.clean("  Kind   of\nBlue ") == "Kind of Blue")
        #expect(Titles.firstLine("\nGift idea\nsecond line") == "Gift idea")
        #expect(Titles.firstLine(String(repeating: "a", count: 100), limit: 10).count == 10)
    }
}

struct MasonryTests {
    @Test func columnCountFitsWidth() {
        #expect(Masonry.columnCount(width: 1000, minColumn: 220, gap: 16) == 4)
        #expect(Masonry.columnCount(width: 100, minColumn: 220, gap: 16) == 1)
        #expect(Masonry.columnCount(width: 5000, minColumn: 220, gap: 16) == 6)
    }

    @Test func fillsShortestColumnFirst() {
        // Tall, short, short: the third goes under the short one.
        let columns = Masonry.columns(heights: [300, 100, 100], count: 2, gap: 0)
        #expect(columns == [[0], [1, 2]])
    }

    @Test func firstRowGoesLeftToRight() {
        let columns = Masonry.columns(heights: [100, 100, 100, 100], count: 4, gap: 16)
        #expect(columns == [[0], [1], [2], [3]])
    }

    @Test func everyItemPlacedOnce() {
        let heights = (0..<50).map { Double(($0 * 37) % 200 + 80) }
        let placed = Masonry.columns(heights: heights, count: 4, gap: 16).flatMap { $0 }.sorted()
        #expect(placed == Array(0..<50))
    }

    @Test func pinLimit() {
        #expect(Pins.canPin(currentlyPinned: 4))
        #expect(!Pins.canPin(currentlyPinned: 5))
    }

    @Test("Blocks only open web links and files")
    func openable() {
        #expect(Links.isOpenable(URL(string: "https://a.com/x")!))
        #expect(Links.isOpenable(URL(string: "HTTP://a.com")!))
        #expect(Links.isOpenable(URL(fileURLWithPath: "/tmp/a.pdf")))
        for text in ["javascript:alert(1)", "x-apple-reminderkit://r", "smb://server/share", "ssh://a.com", "mailto:a@b.c"] {
            #expect(!Links.isOpenable(URL(string: text)!))
        }
    }
}
