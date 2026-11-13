import Foundation
import Testing
@testable import MagpieKit

struct SortSessionTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test("Each action moves on to the next block and counts it")
    func finish() {
        var run = SortSession(inbox: [a, b, c])
        run.finish(.kept)
        #expect(run.current == b && run.kept == 1 && run.sorted == 1 && run.left == 2)
        run.finish(.done)
        run.finish(.deleted)
        #expect(run.current == nil && run.sorted == 3 && run.done == 1 && run.deleted == 1 && run.progress == 1)
    }

    @Test("Skip puts the block at the end of the queue, not back at the start")
    func skip() {
        var run = SortSession(inbox: [a, b, c])
        run.skip()
        #expect(run.queue == [b, c, a])
        run.finish(.kept)
        #expect(run.queue == [c, a])
        #expect(run.sorted == 1)
    }

    @Test("Skipping the last block keeps it")
    func skipLast() {
        var run = SortSession(inbox: [a])
        run.skip()
        #expect(run.queue == [a])
    }

    @Test("The queue follows the Inbox: gone blocks drop out, new ones join at the back")
    func sync() {
        var run = SortSession(inbox: [a, b])
        let d = UUID()
        run.sync(inbox: [d, b])
        #expect(run.queue == [b, d])
    }

    @Test("Progress counts what's sorted out of everything seen")
    func progress() {
        var run = SortSession(inbox: [a, b, c, UUID()])
        run.finish(.kept)
        #expect(run.progress == 0.25)
        #expect(SortSession(inbox: []).progress == 1)
    }
}

struct SortSuggestionTests {
    let reading = UUID(), watch = UUID(), shopping = UUID(), vinyl = UUID(), trip = UUID(), ideas = UUID()
    var collections: [(id: UUID, name: String)] {
        [(reading, "Reading"), (watch, "Watch later"), (shopping, "Shopping"), (vinyl, "Vinyl"), (trip, "Lisbon trip"), (ideas, "Ideas")]
    }

    func suggest(_ site: String, _ kind: String, title: String = "", last: UUID? = nil, in list: [(id: UUID, name: String)]? = nil) -> UUID? {
        SortSuggestion.collection(site: site, kind: kind, title: title, collections: list ?? collections, lastUsedForSite: last)
    }

    @Test("The suggestion comes from the site and kind")
    func fromSiteAndKind() {
        #expect(suggest("youtube.com", "link") == watch)
        #expect(suggest("vimeo.com", "video") == watch)
        #expect(suggest("etsy.com", "link") == shopping)
        #expect(suggest("shop.example.com", "link") == shopping)
        #expect(suggest("discogs.com", "link") == vinyl)
        #expect(suggest("maps.apple.com", "place") == trip)
        #expect(suggest("Note", "note") == ideas)
        #expect(suggest("inkandswitch.com", "link") == reading)
    }

    @Test("With no pile that fits, it falls back to the one used last for that site")
    func fallback() {
        let only: [(id: UUID, name: String)] = [(reading, "Reading"), (vinyl, "Vinyl")]
        #expect(suggest("youtube.com", "video", last: vinyl, in: only) == vinyl)
        #expect(suggest("youtube.com", "video", last: nil, in: only) == nil)
        #expect(suggest("youtube.com", "video", last: UUID(), in: only) == nil)
    }

    @Test("A recipe goes to a cooking pile")
    func recipe() {
        let cook = UUID()
        #expect(suggest("example.com", "link", title: "Pastéis de nata recipe", in: collections + [(cook, "Recipes")]) == cook)
    }
}
