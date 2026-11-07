import AppKit
import SwiftData
import MagpieKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Magpie-self.store build/Magpie.app/Contents/MacOS/Magpie --selftest
/// (scripts/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            let undo = UndoManager()
            func blocks() -> [Block] { (try? context.fetch(FetchDescriptor<Block>())) ?? [] }
            model.scope = .all

            // S-001 save a link; duplicates move to the top instead.
            let before = blocks().count
            let saved = model.save(url: URL(string: "https://www.example.com/post/?utm_source=test")!)
            check("saving a link adds one block", blocks().count == before + 1)
            check("a new link lands in the Inbox", saved.status == .inbox && saved.collection == nil)
            check("the site name is filled in at once", saved.siteName == "example.com")
            let again = model.save(url: URL(string: "http://example.com/post#top")!)
            check("the same page saved twice stays one block", blocks().count == before + 1 && again.uid == saved.uid)
            let video = model.save(url: URL(string: "https://youtu.be/abc")!)
            check("a YouTube link is a video block", video.kind == .video)

            // Text: links become links, anything else becomes a note.
            model.save(.text("Remember the Lisbon bookshop"))
            check("plain text becomes a note", blocks().contains { $0.kind == .note && $0.bodyText == "Remember the Lisbon bookshop" })
            model.save(.text("  discogs.com/release/1  "))
            check("pasted text that is a link becomes a link", blocks().contains { $0.siteName == "discogs.com" })

            // Notes and checklists made by hand.
            model.addNote()
            check("New Note makes a note and selects it", model.block(model.selection)?.kind == .note)
            model.addChecklist()
            check("New Checklist starts with one empty item", model.block(model.selection)?.checklist.count == 1)

            // Delete and undo.
            let total = blocks().count
            model.delete([saved.uid], undo: undo)
            check("delete removes the block", blocks().count == total - 1 && model.block(saved.uid) == nil)
            undo.undo()
            check("undo brings it back with the same id", model.block(saved.uid) != nil && blocks().count == total)

            // Collections, pins and moving.
            for name in ["One", "Two", "Three", "Four", "Five", "Six"] { model.createCollection(named: name) }
            check("the first five collections are pinned", model.pinnedCollections.count == 5)
            let six = model.collections.first { $0.name == "Six" }
            check("the sixth isn't pinned (the limit is 5)", six?.isPinned == false)
            if let six { model.togglePin(six) }
            check("pinning a sixth is refused", model.pinnedCollections.count == 5)
            if let one = model.collections.first(where: { $0.name == "One" }), let block = model.block(saved.uid) {
                model.move(block, to: one, undo: undo)
                check("moving into a collection keeps it out of the Inbox", block.status == .kept && block.collection?.uid == one.uid)
                undo.undo()
                check("undo moves it back to the Inbox", block.status == .inbox && block.collection == nil)
                model.move(block, to: one, undo: nil)
                model.deleteCollection(one)
                check("deleting a collection sends its blocks back to the Inbox", block.collection == nil && block.status == .inbox)
            }

            // S-011 nest, reorder, rename and delete collections.
            if let two = model.collections.first(where: { $0.name == "Two" }),
               let three = model.collections.first(where: { $0.name == "Three" }),
               let four = model.collections.first(where: { $0.name == "Four" }) {
                check("nesting puts a collection inside another", model.place(three, .inside(two.uid)) && three.parent?.uid == two.uid)
                model.place(four, .inside(three.uid))
                check("a collection can't go inside its own child", !model.place(two, .inside(four.uid)) && two.parent == nil)
                let tree = model.collectionTree
                let rowTwo = tree.firstIndex { $0.collection.uid == two.uid } ?? -1
                check("the tree shows children right after their parent, indented",
                      tree.indices.contains(rowTwo + 2) && tree[rowTwo + 1].collection.uid == three.uid && tree[rowTwo + 2].depth == 2)
                model.rename(two, to: "  Second  ")
                check("rename trims and saves the new name", two.name == "Second")
                model.rename(two, to: "   ")
                check("an empty name is ignored", two.name == "Second")

                // Order survives a relaunch: read it back through a second container on the same file.
                let tops = model.collectionTree.filter { $0.depth == 0 }.map(\.collection)
                if let last = tops.last { model.place(last, .before(tops[0].uid)) }
                let expected = model.collectionTree.map(\.collection.name)
                let reopened = try? ModelContainer(for: Block.self, BlockCollection.self, DayActivity.self, configurations: ModelConfiguration(url: Store.url))
                let stored = (try? reopened?.mainContext.fetch(FetchDescriptor<BlockCollection>())) ?? []
                let reread = CollectionTree.flatten(stored.map(\.node)).compactMap { row in stored.first { $0.uid == row.id }?.name }
                check("order and nesting are stored in sortIndex and survive a relaunch", reread == expected, "\(reread) vs \(expected)")

                // Delete: blocks go to the Inbox, the collection inside moves up, nothing else is deleted.
                let note = model.save(url: URL(string: "https://example.com/s-011")!)
                model.move(note, to: three, undo: nil)
                let count = blocks().count
                check("the confirmation counts the blocks that go back", model.deleteMessage(for: three).hasPrefix("Its block goes back to the Inbox"))
                model.deleteCollection(three)
                check("deleting sends its blocks to the Inbox and deletes none", note.collection == nil && note.status == .inbox && blocks().count == count)
                check("the collection inside moves up to the deleted one's parent", four.parent?.uid == two.uid)
            }

            // S-060 Sort Inbox: each action moves on, Skip goes to the back of the queue.
            model.startSorting()
            let queue = model.sortSession.queue
            check("Sort Inbox opens on the newest Inbox block", model.viewMode == .sortInbox && queue.first == model.inboxUIDs.first && !queue.isEmpty)
            if queue.count >= 4, let first = model.sortingBlock {
                model.sortSkip()
                check("Skip puts the block at the end of the queue", model.sortSession.queue.last == first.uid && model.sortSession.current == queue[1])
                let second = model.sortingBlock
                let target = model.collections.first { $0.name == "Second" }
                model.sortMove(to: target, undo: nil)
                check("Move puts it in the collection and goes to the next", second?.collection?.uid == target?.uid && second?.status == .kept && model.sortSession.current == queue[2])
                let third = model.sortingBlock
                model.sortDone()
                check("Done takes it out of the Inbox and goes to the next", third?.status == .done && model.sortSession.current == queue[3])
                let fourth = model.sortingBlock?.uid
                model.sortDelete(undo: undo)
                check("Delete removes it and goes to the next", model.block(fourth) == nil && model.sortSession.current != fourth)
                undo.undo()
                model.syncSorting()
                check("Undo brings it back at the end of the queue", model.sortSession.queue.last == fourth)
                check("the run counts 3 sorted: 1 kept, 1 done, 1 deleted",
                      model.sortSession.sorted == 3 && model.sortSession.kept == 1 && model.sortSession.done == 1 && model.sortSession.deleted == 1)
            }
            let film = model.save(url: URL(string: "https://www.youtube.com/watch?v=sort-test")!)
            let watch = model.createCollection(named: "Watch later")
            check("a YouTube link is suggested for Watch later", model.suggestion(for: film)?.uid == watch?.uid)
            // S-061 Inbox zero: sorting the last block marks today and starts the streak.
            model.startSorting()
            check("today hasn't reached Inbox zero while blocks wait", !model.today.reachedInboxZero && !model.inboxUIDs.isEmpty)
            while model.sortSession.current != nil { model.sortDone() }
            check("sorting the last block reaches Inbox zero", model.inboxUIDs.isEmpty && model.today.reachedInboxZero)
            check("the streak counts today", model.streakDays >= 1)
            check("the run ends on the celebration with its counts", model.sortingBlock == nil && model.sortSession.sorted > 0)
            check("today's activity counts what was saved and sorted", model.today.saved > 0 && model.today.sorted > 0)
            model.show(.gallery)

            // Appearance: ⌃⌘T flips Dark and Light. The choice lives in the app's real
            // preferences, so the test puts it back afterwards.
            let theme = model.appearance
            model.appearance = .dark
            model.toggleAppearance()
            check("Switch Dark and Light goes from Dark to Light", model.appearance == .light && NSApp.appearance?.name == .aqua)
            model.toggleAppearance()
            check("and back to Dark", model.appearance == .dark && NSApp.appearance?.name == .darkAqua)
            model.appearance = .system
            model.toggleAppearance()
            check("from Match my Mac it picks a fixed look", model.appearance != .system)
            model.appearance = theme

            // Scopes.
            let all = blocks()
            check("Inbox shows only Inbox blocks", model.blocks(in: .inbox, from: all).allSatisfy { $0.status == .inbox })
            check("nothing is lost after a save", (try? context.save()) != nil)

            // Copying: a link copies as a link and as text, a note as its text. A private pasteboard,
            // so the test never touches your clipboard.
            let board = NSPasteboard(name: NSPasteboard.Name("Magpie.selftest"))
            let link = model.save(url: URL(string: "https://example.com/copy-me")!)
            model.copy(link, to: board)
            check("Copy Link puts the link on the pasteboard", board.string(forType: .string) == "https://example.com/copy-me"
                  && (board.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.absoluteString == "https://example.com/copy-me")
            model.addNote()
            if let note = model.block(model.selection) {
                note.bodyText = "Remember the bookshop"
                model.copy(note, to: board)
                check("Copy on a note copies its text", board.string(forType: .string)?.contains("Remember the bookshop") == true)
                model.delete([note.uid], undo: nil)
            }
            model.delete([link.uid], undo: nil)
            board.releaseGlobally()

            // S-063 page facts become the block's kind, length and price.
            let shop = model.save(url: URL(string: "https://shop.example.com/lamp")!)
            model.apply(PageFacts(kind: .product, price: 189, currency: "EUR"), to: shop)
            check("a shop page with a price becomes a product with a badge", shop.kind == .product && shop.price == 189 && shop.badge?.contains("189") == true)
            let clip = model.save(url: URL(string: "https://example.com/talk")!)
            model.apply(PageFacts(kind: .video, durationSeconds: 782), to: clip)
            check("a page with a video length becomes a video with “13 min”", clip.kind == .video && clip.minutes == 13 && clip.badge == "13 min")
            let essay = model.save(url: URL(string: "https://example.com/essay")!)
            model.apply(PageFacts(kind: .article, wordCount: 2300), to: essay)
            check("an article gets its read time", essay.kind == .link && essay.minutes == 10)
            let nata = model.save(url: URL(string: "https://example.com/nata")!)
            model.apply(PageFacts(kind: .recipe), to: nata)
            check("a recipe page is marked as a recipe", nata.isRecipe)
            let map = model.save(url: URL(string: "https://maps.google.com/?q=Lisbon")!)
            check("a Google Maps link is a place", map.kind == .place)
            let tower = model.save(url: URL(string: "https://www.google.com/maps/place/Torre+de+Bel%C3%A9m")!)
            check("a place is named from its link", tower.kind == .place && tower.title == "Torre de Belém")
            [shop, clip, essay, nata, map, tower].forEach { model.delete([$0.uid], undo: nil) }

            // S-002 real previews from the network (APP_SELFTEST_NETWORK=1 scripts/selftest.sh).
            if ProcessInfo.processInfo.environment["APP_SELFTEST_NETWORK"] == "1" {
                for link in ["https://www.apple.com/macbook-air/", "https://en.wikipedia.org/wiki/Magpie"] {
                    let block = model.save(url: URL(string: link)!)
                    for _ in 0..<60 where block.enrich == .pending { try? await Task.sleep(for: .seconds(0.5)) }
                    check("preview fetched for \(Links.siteName(block.url!))", block.enrich == .done, "state \(block.enrichRaw)")
                    check("  title filled in: “\(block.title.prefix(50))”", block.title != block.siteName)
                    check("  thumbnail and card color stored", block.thumbnail != nil && block.colorHex != nil,
                          "thumbnail \(block.thumbnail?.count ?? 0) bytes")
                }
                // S-063 real page facts.
                let facts = await Ingest.fetchFacts(URL(string: "https://vimeo.com/76979871")!)
                check("Vimeo's oEmbed gives a video length", (facts?.minutes ?? 0) > 0, "facts \(String(describing: facts))")
                let essay = await Ingest.fetchFacts(URL(string: "https://paulgraham.com/greatwork.html")!)
                check("an essay gets a read time", (essay?.minutes ?? 0) > 10, "facts \(String(describing: essay))")
                let youtube = await Ingest.fetchFacts(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!)
                check("a YouTube page gives a video length", youtube?.durationSeconds != nil, "facts \(String(describing: youtube))")
                let neural = await Ingest.fetchFacts(URL(string: "https://www.youtube.com/watch?v=aircAruvnKk")!)
                check("YouTube's real title comes from oEmbed, not the channel", neural?.title?.hasPrefix("But what is a neural network") == true && neural?.author == "3Blue1Brown",
                      "title \(neural?.title ?? "nil")")
                let local = await Ingest.fetchFacts(URL(string: "https://www.inkandswitch.com/local-first/")!)
                check("a meta refresh is followed (inkandswitch.com)", local?.redirectedTo != nil && (local?.minutes ?? 0) > 10,
                      "facts \(String(describing: local))")
                for shop in ["https://www.ikea.com/us/en/p/billy-bookcase-white-20522046/"] {
                    let product = await Ingest.fetchFacts(URL(string: shop)!)
                    check("a shop page gives a price (\(Links.siteName(URL(string: shop)!)))", product?.price != nil, "facts \(String(describing: product))")
                }
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
