import Foundation
import Testing
@testable import MagpieKit

struct ExportTests {
    static func sample() -> LibraryExport {
        let reading = UUID(), nested = UUID(), jazz = UUID(), item = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000.123)
        return LibraryExport(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            collections: [
                .init(uid: reading, name: "Reading", colorHex: 0x7FD9D3, sortIndex: 1, isPinned: true, pinIndex: 0, createdAt: created,
                      parent: nil, sortOrder: "quickest", viewMode: "journal", shuffleSeed: 42, expiryDays: 30),
                .init(uid: nested, name: "Essays & notes", colorHex: 0xE8A27A, sortIndex: 1.5, isPinned: false, pinIndex: 0, createdAt: created,
                      parent: reading, sortOrder: nil, viewMode: nil, shuffleSeed: 0, expiryDays: nil),
            ],
            tags: [.init(uid: jazz, name: "Jazz", colorHex: 0x8FB5E8, createdAt: created)],
            blocks: [
                .init(uid: UUID(), kind: "link", url: "https://example.com/a?x=1&y=2", normalizedURL: "https://example.com/a?x=1&y=2",
                      title: "“Quotes” <and> ampersands & Ünïcödé", siteName: "example.com", note: "why", bodyText: "",
                      checklist: [], image: "images/x.jpg", imageAspect: 1.6, colorHex: 0x123456, status: "kept",
                      statusBeforeArchive: nil, createdAt: created, openedAt: created.addingTimeInterval(60), finishedAt: nil,
                      expiresAt: created.addingTimeInterval(86_400), expiredAt: nil, lastShownAt: nil, collection: nested,
                      tags: [jazz], minutes: 13, price: 189.5, currency: "EUR", isRecipe: false, pile: "cook", timesSkipped: 2,
                      ocrText: "text in the image", sortIndex: 1.25),
                .init(uid: UUID(), kind: "checklist", url: nil, normalizedURL: nil, title: "Lisbon weekend", siteName: "Checklist",
                      note: "", bodyText: "", checklist: [.init(id: item, text: "Book the train", done: true)], image: nil,
                      imageAspect: 0, colorHex: nil, status: "archived", statusBeforeArchive: "inbox", createdAt: created,
                      openedAt: nil, finishedAt: nil, expiresAt: nil, expiredAt: created, lastShownAt: created, collection: nil,
                      tags: [], minutes: nil, price: nil, currency: nil, isRecipe: false, pile: nil, timesSkipped: 0,
                      ocrText: nil, sortIndex: 0),
            ],
            days: [.init(day: 739_000, saved: 3, sorted: 2, reachedInboxZero: true, spins: 1, finished: 1)]
        )
    }

    @Test("The JSON keeps every field, collection and tag: reading it back gives the same library")
    func roundTrip() throws {
        let library = Self.sample()
        let back = try LibraryExport.read(try library.json())
        #expect(back == library)
    }

    @Test("The JSON is readable: indented, with dates people can read")
    func readable() throws {
        let text = String(decoding: try Self.sample().json(), as: UTF8.self)
        #expect(text.contains("\n  \"blocks\" : [") && text.contains("2023-11-14T22:13:20.123Z"))
    }

    @Test("The bookmarks file is the format browsers import, and reads back as the same tree")
    func bookmarksHTML() {
        let added = Date(timeIntervalSince1970: 1_700_000_000)
        let tree = BookmarkFolder(id: "", name: "", links: [.init(url: URL(string: "https://example.com/loose")!, title: "Loose", added: added)],
                                  folders: [BookmarkFolder(id: "Reading", name: "Reading",
                                                           links: [.init(url: URL(string: "https://example.com/?a=1&b=2")!, title: "A & B <c>", added: added)],
                                                           folders: [BookmarkFolder(id: "Reading/Essays", name: "Essays",
                                                                                    links: [.init(url: URL(string: "https://example.com/e")!, title: "E", added: nil)],
                                                                                    folders: [])])])
        let html = BookmarkFile.write(tree)
        #expect(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        let back = BookmarkFile.parse(html)
        #expect(back.links.map(\.title) == ["Loose"] && back.links.first?.added == added)
        #expect(back.folders.first?.name == "Reading" && back.folders.first?.links.first?.title == "A & B <c>")
        #expect(back.folders.first?.links.first?.url.absoluteString == "https://example.com/?a=1&b=2")
        #expect(back.folders.first?.folders.first?.name == "Essays" && back.total == 3)
    }
}
