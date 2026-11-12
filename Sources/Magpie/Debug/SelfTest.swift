import AppKit
import SwiftData
import SwiftUI
import MagpieKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Magpie-self.store build/Magpie.app/Contents/MacOS/Magpie --selftest
/// (scripts/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate. Starts as a failure, so a run that quits
    /// before it finishes (a crash in a check, or closing the window quitting the app) exits 1.
    static var exitCode: Int32 = 1
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
                let reopened = try? ModelContainer(for: Block.self, BlockCollection.self, DayActivity.self, Tag.self, configurations: ModelConfiguration(url: Store.url))
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
            model.startSorting()
            if let card = model.sortingBlock {
                model.isRenamingSortBlock = true
                check("while renaming a card, the sorting keys are off", !model.canSortNow)
                model.rename(card, to: "  A better   name ")
                model.isRenamingSortBlock = false
                check("renaming in Sort Inbox saves the tidied title and keeps the card", card.title == "A better name"
                      && model.sortingBlock?.uid == card.uid && model.canSortNow)
                model.rename(card, to: "   ")
                check("an empty title is ignored", card.title == "A better name")
            }
            // S-061 Inbox zero: sorting the last block marks today.
            model.startSorting()
            check("today hasn't reached Inbox zero while blocks wait", !model.today.reachedInboxZero && !model.inboxUIDs.isEmpty)
            while model.sortSession.current != nil { model.sortDone() }
            check("sorting the last block reaches Inbox zero", model.inboxUIDs.isEmpty && model.today.reachedInboxZero)
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

            // S-070–S-072 Lucky Dip, picking from a collection (#3).
            let essayToRead = model.save(url: URL(string: "https://example.com/long-read")!)
            essayToRead.minutes = 25
            let quickRead = model.save(url: URL(string: "https://example.com/quick-read")!)
            quickRead.minutes = 5
            let film2 = model.save(url: URL(string: "https://vimeo.com/123")!)
            film2.minutes = 40
            if let dip = model.createCollection(named: "Dip test", pin: false),
               let inner = model.createCollection(named: "Dip inner", pin: false) {
                inner.parent = dip
                model.move(essayToRead, to: dip, undo: nil, announce: false)
                model.move(quickRead, to: dip, undo: nil, announce: false)
                model.move(film2, to: inner, undo: nil, announce: false)
                let fromDip = Set(model.dipBlocks(from: dip.uid).map(\.uid))
                check("Lucky Dip picks from a collection and the ones inside it", fromDip == [essayToRead.uid, quickRead.uid, film2.uid])
                check("…and from everything", Set(model.dipBlocks(from: nil).map(\.uid)).isSuperset(of: fromDip))
                check("the start button says what you'll do", essayToRead.startVerb == "Start reading" && film2.startVerb == "Start watching")
                model.dipCollection = dip.uid
            }
            model.show(.luckyDip)
            model.dipMaxMinutes = 10
            model.spin(reduceMotion: true)
            try? await Task.sleep(for: .milliseconds(200))
            check("Randomize picks one block that fits the time", model.dipPick?.uid == quickRead.uid && model.spinsToday == 1)
            model.dipMaxMinutes = nil
            model.spin(reduceMotion: true)
            try? await Task.sleep(for: .milliseconds(200))
            check("Spin again picks a different block and uses a re-spin", model.dipPick != nil && model.dipPick?.uid != quickRead.uid && model.respinsLeft == 1)
            model.spin(reduceMotion: true)
            try? await Task.sleep(for: .milliseconds(200))
            check("after two re-spins no more are allowed today", model.respinsLeft == 0 && !model.canSpin)
            if let pick = model.dipPick {
                model.notToday(pick)
                check("Not today counts a skip and clears the pick", pick.timesSkipped == 1 && model.dipPick == nil)
                pick.timesSkipped = 3
                check("after 3 skips the details ask “Still want this?”", pick.timesSkipped >= LuckyDip.skipsBeforeAsking)
                model.keepWanting(pick)
                check("“Keep it” resets the skips", pick.timesSkipped == 0)
            }
            model.today.pickUID = essayToRead.uid
            model.startPick(essayToRead)
            check("Start marks it In progress and shows it on Lucky Dip", essayToRead.status == .inProgress && model.inProgressBlock?.uid == essayToRead.uid)
            check("Start opens its page (recorded, not opened, during the self-test)", model.lastOpenedURL == essayToRead.url)
            check("an In progress block isn't picked again", !model.dipBlocks(from: model.dipCollection).contains { $0.uid == essayToRead.uid })
            model.finishPick(essayToRead)
            check("Finish marks it done with a finished date", essayToRead.status == .done && essayToRead.finishedAt != nil && model.inProgressBlock == nil)
            check("a finished pick counts toward the dip streak and this week", model.dipStreak >= 1 && model.finishedThisWeek >= 1 && model.today.finished >= 1)
            if let dip = model.collection(model.dipCollection) {
                let inner = model.collections.first { $0.parent?.uid == dip.uid }
                [essayToRead, quickRead, film2].forEach { model.move($0, to: nil, undo: nil, announce: false) }
                if let inner { model.deleteCollection(inner) }
                model.deleteCollection(dip)
                check("a deleted collection falls back to Everything", model.dipCollection == nil)
            }
            model.show(.gallery)

            // S-014 and S-015 tags.
            let record = model.save(url: URL(string: "https://www.discogs.com/release/tag-test")!)
            let other = model.save(url: URL(string: "https://bandcamp.com/tag-test")!)
            model.addTags("Jazz, vinyl", to: record)
            model.addTags("jazz", to: other)
            let jazzTags = model.tags.filter { Tags.key($0.name) == "jazz" }
            check("“Jazz” and “jazz” are one tag", jazzTags.count == 1 && (other.tags ?? []).first?.uid == jazzTags.first?.uid)
            model.addTags("JAZZ", to: record)
            check("a tag isn't added twice to one block", (record.tags ?? []).count == 2)
            if let jazz = jazzTags.first, let vinyl = model.tags.first(where: { $0.name == "vinyl" }) {
                model.scope = .tag(jazz.uid)
                let shown = model.blocks(in: model.scope, from: blocks())
                check("a tag shows every block that has it", Set(shown.map(\.uid)) == [record.uid, other.uid])
                model.renameTag(vinyl, to: "Records")
                check("renaming a tag keeps it on its blocks", vinyl.name == "Records" && (record.tags ?? []).contains { $0.uid == vinyl.uid })
                model.renameTag(vinyl, to: "JAZZ")
                check("renaming to an existing tag's name merges the two", model.tag(vinyl.uid) == nil
                      && (record.tags ?? []).map(\.uid) == [jazz.uid] && model.tags.filter { Tags.key($0.name) == "jazz" }.count == 1)
                model.deleteTag(jazz)
                check("deleting a tag removes it from blocks and keeps the blocks",
                      model.tags.isEmpty && (record.tags ?? []).isEmpty && model.block(record.uid) != nil && model.block(other.uid) != nil)
                check("the Gallery goes back to All when its tag is deleted", model.scope == .all)
            }
            model.delete([record.uid, other.uid], undo: nil)

            // S-065 sort orders and S-067 Journal, remembered per place.
            if let second = model.collections.first(where: { $0.name == "Second" }), let five = model.collections.first(where: { $0.name == "Five" }) {
                let quick = model.save(url: URL(string: "https://example.com/order-quick")!)
                quick.minutes = 3
                let slow = model.save(url: URL(string: "https://example.com/order-slow")!)
                slow.minutes = 40
                let unknown = model.save(url: URL(string: "https://example.com/order-unknown")!)
                [quick, slow, unknown].forEach { model.move($0, to: second, undo: nil) }
                model.setOrder(.quickest, for: .collection(second.uid))
                let shown = model.ordered(model.blocks(in: .collection(second.uid), from: blocks()), in: .collection(second.uid))
                let position = { (block: Block) in shown.firstIndex { $0.uid == block.uid } ?? -1 }
                let knownBeforeUnknown = shown.drop { $0.minutes != nil }.allSatisfy { $0.minutes == nil }
                check("Quickest lists short first and unknown length last",
                      position(quick) < position(slow) && position(slow) < position(unknown) && knownBeforeUnknown)
                check("each collection remembers its own order",
                      model.order(for: .collection(second.uid)) == .quickest && model.order(for: .collection(five.uid)) == .newest)
                model.setOrder(.shuffle, for: .collection(second.uid))
                let firstSeed = second.shuffleSeed
                model.setOrder(.shuffle, for: .collection(second.uid))
                check("choosing Shuffle again deals a new order", second.shuffleSeed != firstSeed)
                model.scope = .collection(second.uid)
                model.show(.journal)
                model.scope = .collection(five.uid)
                check("a collection opens in Gallery until switched", model.viewMode == .gallery)
                model.scope = .collection(second.uid)
                check("each collection remembers Journal or Gallery", model.viewMode == .journal && second.viewModeRaw == "journal")
                model.show(.gallery)
                model.scope = .all
                [quick, slow, unknown].forEach { model.delete([$0.uid], undo: nil) }
            }

            // S-022 archive, S-021 expiry, S-020 Rediscover.
            if let second = model.collections.first(where: { $0.name == "Second" }) {
                let old = model.save(url: URL(string: "https://example.com/archive-me")!)
                model.move(old, to: second, undo: nil)
                model.archive(old)
                let all = blocks()
                check("archived blocks leave All and their collection", !model.blocks(in: .all, from: all).contains { $0.uid == old.uid }
                      && !model.blocks(in: .collection(second.uid), from: all).contains { $0.uid == old.uid })
                check("…and show in the Archive", model.blocks(in: .archive, from: all).contains { $0.uid == old.uid })
                model.unarchive(old)
                check("Unarchive restores the previous status", old.status == .kept && old.collection?.uid == second.uid)

                let before = model.save(url: URL(string: "https://example.com/before-expiry")!)
                model.move(before, to: second, undo: nil)
                model.setExpiry(second, days: 30)
                check("changing the setting doesn't change existing blocks", before.expiresAt == nil)
                let fresh = model.save(url: URL(string: "https://example.com/after-expiry")!)
                model.move(fresh, to: second, undo: nil)
                let days = (fresh.expiresAt?.timeIntervalSinceNow ?? 0) / 86_400
                check("new blocks expire after the collection's days", days > 29.9 && days <= 30)
                model.keep(fresh)
                check("Keep clears an expiry", fresh.expiresAt == nil)
                fresh.expiresAt = Date.now.addingTimeInterval(-60)
                model.expireDue()
                check("an expired block is archived, not deleted, and shows under Expired", fresh.status == .archived
                      && model.block(fresh.uid) != nil && model.blocks(in: .expired, from: blocks()).contains { $0.uid == fresh.uid })
                model.setExpiry(second, days: nil)

                // Rediscover: old saves only, five a day, each action moves on.
                let olds = (0..<7).map { index in
                    let block = model.save(url: URL(string: "https://example.com/old-\(index)")!)
                    model.move(block, to: second, undo: nil)
                    block.createdAt = Date.now.addingTimeInterval(-Double(30 + index) * 86_400)
                    return block
                }
                let recent = model.save(url: URL(string: "https://example.com/recent")!)
                model.startRediscover()
                let picks = model.rediscoverIDs
                check("Rediscover picks 5 old saves, none recent", picks.count == 5 && !picks.contains(recent.uid)
                      && Set(picks).isSubset(of: Set(olds.map(\.uid) + [before.uid, old.uid] + blocks().filter { $0.createdAt < Date.now.addingTimeInterval(-14 * 86_400) }.map(\.uid))))
                let first = model.rediscoverBlock
                model.rediscoverKeep()
                check("Keep sets when it was last shown and moves on", first?.lastShownAt != nil && model.rediscoverBlock?.uid == picks[1])
                let second2 = model.rediscoverBlock
                model.rediscoverSkip()
                check("Skip counts a skip", (second2?.timesSkipped ?? 0) == 1)
                let third = model.rediscoverBlock
                model.rediscoverArchive()
                check("Archive archives it", third?.status == .archived)
                model.rediscoverKeep()
                model.rediscoverKeep()
                check("after five: today's five are done", model.rediscoverBlock == nil && model.today.rediscoverDone == 5)
                model.startRediscover()
                check("opening again today doesn't pick five more", model.rediscoverIDs == picks)
                model.show(.gallery)
                (olds + [recent, before, fresh, old]).forEach { model.delete([$0.uid], undo: nil) }
            }

            // S-031 search, S-073/074 totals.
            let essay2 = model.save(url: URL(string: "https://example.com/cafe")!)
            essay2.title = "Café Santiago in Porto"
            let archivedNote = model.save(url: URL(string: "https://example.com/lisbon-guide")!)
            archivedNote.title = "Lisbon guide"
            model.addTags("travel", to: archivedNote)
            model.archive(archivedNote)
            model.startSearch()
            check("search ignores case and accents", model.searchResults("CAFE porto", in: blocks()).map(\.uid) == [essay2.uid])
            check("search finds archived blocks and tags", model.searchResults("trav", in: blocks()).contains { $0.uid == archivedNote.uid })
            check("search matches the start of words only", model.searchResults("antiago", in: blocks()).isEmpty)
            model.endSearch()
            // Text in an image: render a picture with words and read them back with Vision.
            let picture = NSImage(size: NSSize(width: 600, height: 200), flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                ("MAGPIE KEEPS VINYL" as NSString).draw(at: NSPoint(x: 30, y: 80),
                    withAttributes: [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.black])
                return true
            }
            if let tiff = picture.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let text = await Ingest.recognizeText(png)
                check("text in images is read with Vision", text?.uppercased().contains("VINYL") == true, "read \(text ?? "nothing")")
            }
            // 5,000 blocks: results within 100 ms.
            let many = (0..<5000).map { index in
                let block = Block(kind: .link, title: "Sample block \(index) about records and coffee")
                block.siteName = "site\(index % 40).com"
                context.insert(block)
                return block
            }
            let all5000 = blocks()
            _ = model.searchResults("warm", in: all5000)   // the first search builds the cache, like the first letter typed
            let started = Date.now
            let found = model.searchResults("coff site3", in: all5000)
            let elapsed = Date.now.timeIntervalSince(started)
            print("SELFTEST note: search over 5,000 blocks took \(Int(elapsed * 1000)) ms")
            // 100 ms on a Mac; shared CI runners (CI=true) are slower, so they get 500 ms, like the unit test.
            let limit = ProcessInfo.processInfo.environment["CI"] == "true" ? 0.5 : 0.1
            check("search over 5,000 blocks finds the right blocks", found.count >= 125, "\(found.count) found")
            check("search over 5,000 blocks takes under \(Int(limit * 1000)) ms", elapsed < limit, "\(Int(elapsed * 1000)) ms")
            many.forEach(context.delete)
            [essay2, archivedNote].forEach { model.delete([$0.uid], undo: nil) }

            let film3 = model.save(url: URL(string: "https://vimeo.com/totals")!)
            film3.minutes = 130
            let film4 = model.save(url: URL(string: "https://vimeo.com/totals2")!)
            film4.minutes = 60
            let lamp = model.save(url: URL(string: "https://shop.example.com/totals")!)
            lamp.price = 189
            lamp.currency = "EUR"
            let mug = model.save(url: URL(string: "https://shop.example.com/totals2")!)
            mug.price = 60
            mug.currency = "USD"
            check("a collection's video total sums known lengths", model.videoTotal([film3, film4, lamp]) == "3 h 10 min")
            check("the wishlist total is kept per currency", model.priceTotal([lamp, mug])?.contains("+") == true)
            [film3, film4, lamp, mug].forEach { model.delete([$0.uid], undo: nil) }

            // S-030 Quick Save: the panel saves to the chosen collection, Escape cancels.
            if let second = model.collections.first(where: { $0.name == "Second" }) {
                let board2 = NSPasteboard(name: NSPasteboard.Name("Magpie.selftest.quick"))
                board2.clearContents()
                board2.setString("https://example.com/quick-save", forType: .string)
                let draft = QuickSaveSource.clipboard(board2)
                check("Quick Save reads a link from the clipboard", draft.content == .web(URL(string: "https://example.com/quick-save")!)
                      && draft.source == "From the clipboard")
                // #5: in Firefox, which can't share its tab, the panel says the link is the clipboard's.
                let fromFirefox = await QuickSaveSource.capture(frontApp: "org.mozilla.firefox", pasteboard: board2)
                check("in Firefox, Quick Save says it's using the clipboard and why",
                      fromFirefox.content == draft.content && fromFirefox.source.contains("Firefox") && fromFirefox.source.contains("clipboard"),
                      fromFirefox.source)
                let elsewhere = await QuickSaveSource.capture(frontApp: "com.apple.TextEdit", pasteboard: board2)
                check("…and in an app that isn't a browser it saves the clipboard", elsewhere.source == "From the clipboard")
                check("Chrome, Arc, Brave and Edge are read like Safari",
                      ["com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
                        .allSatisfy { QuickSaveSource.browsers[$0]?.isSafari == false } && QuickSaveSource.browsers["com.apple.Safari"]?.isSafari == true)
                board2.clearContents()
                check("an empty clipboard says so", QuickSaveSource.clipboard(board2).content == .nothing)
                board2.releaseGlobally()

                let panel = model.quickSavePanel
                panel.show(draft)
                check("the Quick Save panel opens", panel.isVisible)
                panel.close()
                check("Escape (Cancel) closes it without saving", !panel.isVisible
                      && !blocks().contains { $0.urlString == "https://example.com/quick-save" })
                panel.show(draft)
                panel.save(QuickSavePanel.Edited(draft: draft, title: "Quick one", collection: second.uid, tags: "fast, later", note: "From the panel"))
                let quick = blocks().first { $0.urlString == "https://example.com/quick-save" }
                check("Return (Save) saves to the chosen collection with its tags and note, and closes",
                      !panel.isVisible && quick?.collection?.uid == second.uid && quick?.title == "Quick one"
                      && (quick?.tags ?? []).count == 2 && quick?.note == "From the panel")
                let text = model.quickSave(QuickSavePanel.Edited(draft: QuickSaveDraft(content: .text("Buy film for the trip"), title: "Buy film", source: ""),
                                                                 title: "Buy film", collection: nil, tags: "", note: ""))
                check("text from the clipboard becomes a note in the Inbox", text?.kind == .note && text?.status == .inbox)
                [quick, text].compactMap { $0 }.forEach { model.delete([$0.uid], undo: nil) }
                model.tags.filter { ["fast", "later"].contains($0.name) }.forEach(model.deleteTag)
            }

            // S-066 Manual order and S-032 Quick Look.
            if let five = model.collections.first(where: { $0.name == "Five" }) {
                let row = (0..<4).map { index -> Block in
                    let block = model.save(url: URL(string: "https://example.com/manual-\(index)")!)
                    model.move(block, to: five, undo: nil)
                    block.createdAt = Date.now.addingTimeInterval(Double(-index) * 60)
                    return block
                }
                let place = Scope.collection(five.uid)
                let seen = model.ordered(model.blocks(in: place, from: blocks()), in: place)
                let lastSeen = seen.last!, firstSeen = seen.first!
                model.reorder(lastSeen.uid, onto: firstSeen.uid, shown: seen, in: place)
                let after = model.ordered(model.blocks(in: place, from: blocks()), in: place).map(\.uid)
                var expected = seen.map(\.uid)
                expected.removeLast()
                expected.insert(lastSeen.uid, at: 0)
                check("dragging while sorted by Newest switches to Manual and keeps what you see", model.order(for: place) == .manual && after == expected)
                let others = seen.filter { $0.uid != lastSeen.uid }.map(\.sortIndex)
                check("a drop takes a new index, and the others keep theirs (no renumbering)",
                      others == [1, 2, 3] && lastSeen.sortIndex == 0)
                let picture = model.saveImage(Data(), name: "Empty")
                let dot = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
                picture.thumbnail = dot.tiffRepresentation
                model.quickLook(picture)
                check("Quick Look shows a block's picture", model.quickLookURL?.isFileURL == true)
                model.quickLook(picture)
                check("…and Space again closes it", model.quickLookURL == nil)
                (row + [picture]).forEach { model.delete([$0.uid], undo: nil) }
            }

            // S-042 import bookmarks.
            let already = model.save(url: URL(string: "https://example.org/already-saved")!)
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
              <DT><H3>Imported Bar</H3>
              <DL><p>
                <DT><A HREF="http://example.org/already-saved/" ADD_DATE="1700000000">Same page again</A>
                <DT><H3>Imported Recipes</H3>
                <DL><p>
                  \((0..<8).map { "<DT><A HREF=\"https://bookmarks.invalid/recipe-\($0)\" ADD_DATE=\"1700000\($0)00\">Recipe \($0)</A>" }.joined(separator: "\n"))
                </DL><p>
              </DL><p>
              <DT><A HREF="https://bookmarks.invalid/loose">Loose</A>
            </DL><p>
            """
            model.previewBookmarks(html, file: "bookmarks.html")
            if let plan = model.bookmarkImport {
                let result = model.importBookmarks(plan)
                try? await Task.sleep(for: .milliseconds(1500))
                check("previews for imported bookmarks load a few at a time", model.importInFlightMost > 0
                      && model.importInFlightMost <= AppModel.importBatch, "\(model.importInFlightMost) at once")
                let bar = model.collections.first { $0.name == "Imported Bar" }
                let recipes = model.collections.first { $0.name == "Imported Recipes" }
                check("bookmark folders become nested collections", recipes?.parent?.uid == bar?.uid && (recipes?.blocks ?? []).count == 8)
                check("imported collections aren't pinned", bar?.isPinned == false && recipes?.isPinned == false)
                check("duplicates are skipped and counted", result.duplicates == 1 && result.saved == 9)
                let loose = blocks().first { $0.urlString == "https://bookmarks.invalid/loose" }
                check("links outside folders go to the Inbox", loose?.status == .inbox)
                check("imported bookmarks keep their date", (recipes?.blocks ?? []).allSatisfy { $0.createdAt < Date(timeIntervalSince1970: 1_700_100_000) })
                for block in (recipes?.blocks ?? []) + [loose].compactMap({ $0 }) { model.delete([block.uid], undo: nil) }
                [recipes, bar].compactMap { $0 }.forEach(model.deleteCollection)
            } else {
                check("the bookmarks file is read", false)
            }
            model.delete([already.uid], undo: nil)

            // S-041 Dock drop and S-075 screenshot.
            let folder = FileManager.default.temporaryDirectory.appending(path: "magpie-selftest-dock")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let webloc = folder.appending(path: "Dock link.webloc")
            try? PropertyListSerialization.data(fromPropertyList: ["URL": "https://example.com/from-dock"], format: .xml, options: 0).write(to: webloc)
            let shot = NSImage(size: NSSize(width: 640, height: 200), flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                ("RECEIPT TOTAL 42 EUROS" as NSString).draw(at: NSPoint(x: 30, y: 80),
                    withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.black])
                return true
            }
            let png = shot.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()
            let imageFile = folder.appending(path: "Dock picture.png")
            try? png.write(to: imageFile)
            if let five = model.collections.first(where: { $0.name == "Five" }) { model.scope = .collection(five.uid) }
            let dropped = model.receive([URL(string: "https://example.com/dock-link")!, webloc, imageFile])
            check("links, .webloc files and images dropped on the Dock are saved",
                  dropped.count == 3 && dropped.contains { $0.urlString == "https://example.com/from-dock" } && dropped.contains { $0.kind == .image })
            check("…to the Inbox, whatever the window shows", dropped.allSatisfy { $0.status == .inbox && $0.collection == nil })
            model.toast = nil
            let quiet = model.receive([URL(string: "https://example.com/quiet-drop")!], quietly: true)
            check("a quick Dock drop saves without a message in the window", quiet.count == 1 && model.toast == nil, "message: \(model.toast ?? "")")
            DropHUD.show("Saved to Inbox")
            check("…and shows “Saved to Inbox” by the Dock instead", DropHUD.isVisible)
            quiet.forEach { model.delete([$0.uid], undo: nil) }
            // A link file can hold any kind of address; only web links become links, and a block
            // with another kind (from an edited export, say) is never opened.
            let sneaky = folder.appending(path: "Sneaky.webloc")
            try? PropertyListSerialization.data(fromPropertyList: ["URL": "x-apple-reminderkit://r"], format: .xml, options: 0).write(to: sneaky)
            let kept = model.receive([sneaky], quietly: true)
            check("a link file with a non-web address is kept as a file, not as that address",
                  kept.count == 1 && kept[0].kind == .file && kept[0].url?.isFileURL == true, "\(kept.map(\.urlString))")
            kept.forEach { model.delete([$0.uid], undo: nil) }
            let planted = Block(kind: .link, title: "Planted")
            planted.urlString = "x-apple-reminderkit://r"
            model.context.insert(planted)
            let openedBefore = model.lastOpenedURL
            model.open(planted)
            check("opening a block with a non-web address does nothing", model.lastOpenedURL == openedBefore)
            model.delete([planted.uid], undo: nil)
            model.scope = .all
            let screenshot = model.saveScreenshot(png)
            for _ in 0..<40 where screenshot.bodyText.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            check("a screenshot is an image block in the Inbox with its text as body text",
                  screenshot.kind == .image && screenshot.status == .inbox && screenshot.bodyText.uppercased().contains("RECEIPT"),
                  "text: \(screenshot.bodyText)")
            check("…and search finds it by that text", model.searchResults("receipt", in: blocks()).contains { $0.uid == screenshot.uid })
            (dropped + [screenshot]).forEach { model.delete([$0.uid], undo: nil) }
            try? FileManager.default.removeItem(at: folder)

            // #2 Choose Picture: offered for web links, not places or notes; choosing sets the
            // picture and color and is remembered (a refresh keeps it, and so does an export).
            let pictured = model.save(url: URL(string: "https://example.com/choose-a-picture")!)
            let place = model.save(url: URL(string: "https://maps.apple.com/?q=Lisbon&ll=38.7,-9.1")!)
            model.addNote()
            let note = model.block(model.selection)
            check("Choose Picture is offered for links, not places or notes",
                  model.canChoosePicture(pictured) && !model.canChoosePicture(place) && note.map { !model.canChoosePicture($0) } == true)
            model.choosePicture(pictured)
            check("…and opens the chooser for that block", model.pictureChoice?.uid == pictured.uid && model.pictureChoice?.choices == nil)
            if let chosen = await Ingest.process(png) {
                model.setPicture(chosen, for: pictured)
                check("choosing a picture sets it and its color, remembers it was chosen, and closes the chooser",
                      pictured.thumbnail == chosen.jpeg && pictured.pictureChosen && pictured.colorHex == chosen.color.map(Int.init)
                      && model.pictureChoice == nil)
            }
            [pictured, place].forEach { model.delete([$0.uid], undo: nil) }
            if let note { model.delete([note.uid], undo: nil) }

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
                // #2 real picture choices from a page.
                let pictures = await Ingest.fetchPictureChoices(URL(string: "https://en.wikipedia.org/wiki/Magpie")!)
                check("a real page offers several pictures to choose from", pictures.count >= 2, "\(pictures.count) pictures")
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

            // S-053 Settings: default expiry for new collections, Rediscover's Dock badge.
            // Both live in your real preferences, so the test puts your values back.
            let keepExpiry = model.defaultExpiryDays, keepBadge = model.rediscoverDockBadge
            model.defaultExpiryDays = 14
            let fresh14 = model.createCollection(named: "Settings expiry test", pin: false)
            check("new collections get the default expiry from Settings", fresh14?.defaultExpiryDays == 14)
            model.previewBookmarks("<DL><p><DT><H3>Settings import test</H3><DL><p><DT><A HREF=\"https://settings.invalid/a\">A</A></DL><p></DL><p>", file: "t.html")
            if let plan = model.bookmarkImport { model.importBookmarks(plan) }
            let importedFolder = model.collections.first { $0.name == "Settings import test" }
            check("imported bookmark folders don't get it", importedFolder != nil && importedFolder?.defaultExpiryDays == nil)
            model.rediscoverDockBadge = true
            check("the Dock badge shows what Rediscover has waiting", NSApp.dockTile.badgeLabel == (model.rediscoverWaiting > 0 ? "\(model.rediscoverWaiting)" : nil))
            model.rediscoverDockBadge = false
            check("…and goes away when turned off", NSApp.dockTile.badgeLabel == nil)
            for item in [fresh14, importedFolder].compactMap({ $0 }) {
                (item.blocks ?? []).forEach { model.delete([$0.uid], undo: nil) }
                model.deleteCollection(item)
            }
            model.defaultExpiryDays = keepExpiry
            model.rediscoverDockBadge = keepBadge

            // S-054 export everything, and read it back with no loss.
            do {
                let picture = model.save(url: URL(string: "https://example.com/export-picture")!)
                let dot = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.systemOrange.setFill(); rect.fill(); return true }
                picture.thumbnail = dot.tiffRepresentation
                picture.pictureChosen = true
                model.addTags("export, Jazz", to: picture)
                picture.note = "Why: “quotes” & ampersands"
                let pictureID = picture.uid   // read before the library is emptied below
                let base = FileManager.default.temporaryDirectory.appending(path: "magpie-selftest-export")
                try? FileManager.default.removeItem(at: base)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let first = try model.export(into: base)
                let before = try LibraryExport.read(Data(contentsOf: first.appending(path: "library.json")))
                let webLinks = before.blocks.filter { $0.url?.hasPrefix("http") == true }.count
                let html = try String(contentsOf: first.appending(path: "bookmarks.html"), encoding: .utf8)
                check("the bookmarks file holds every web link, in the format browsers import",
                      html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>") && BookmarkFile.parse(html).total == webLinks,
                      "\(BookmarkFile.parse(html).total) of \(webLinks)")
                check("pictures are written as files next to library.json",
                      before.blocks.compactMap(\.image).allSatisfy { FileManager.default.fileExists(atPath: first.appending(path: $0).path) }
                      && before.blocks.contains { $0.image != nil })

                // Empty the library, read the export back, export again, and compare.
                for block in blocks() { context.delete(block) }
                for item in (try? context.fetch(FetchDescriptor<BlockCollection>())) ?? [] { context.delete(item) }
                for item in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] { context.delete(item) }
                for item in (try? context.fetch(FetchDescriptor<DayActivity>())) ?? [] { context.delete(item) }
                model.save()
                check("(the library is empty before reading the export back)", blocks().isEmpty && model.collections.isEmpty)
                let added = try model.importExport(first.appending(path: "library.json"))
                let second = try model.export(into: base)
                let after = try LibraryExport.read(Data(contentsOf: second.appending(path: "library.json")))
                func normal(_ library: LibraryExport) -> LibraryExport {
                    var copy = library
                    copy.exportedAt = .distantPast
                    copy.blocks.sort { $0.uid.uuidString < $1.uid.uuidString }
                    copy.collections.sort { $0.uid.uuidString < $1.uid.uuidString }
                    copy.tags.sort { $0.uid.uuidString < $1.uid.uuidString }
                    for index in copy.blocks.indices { copy.blocks[index].tags.sort { $0.uuidString < $1.uuidString } }
                    return copy
                }
                check("reading an export back loses nothing: every block, field, collection, tag and day",
                      added == before.blocks.count && normal(before) == normal(after), "\(added) of \(before.blocks.count) blocks")
                let pictureBefore = try Data(contentsOf: first.appending(path: "images/\(pictureID.uuidString).jpg"))
                let pictureAfter = model.block(pictureID)?.thumbnail
                check("…pictures included", pictureAfter == pictureBefore)
                check("…and a picture chosen by hand stays chosen", model.block(pictureID)?.pictureChosen == true
                      && before.blocks.first { $0.uid == pictureID }?.pictureChosen == true)
                check("reading the same export twice adds nothing", try model.importExport(first.appending(path: "library.json")) == 0)
                try? FileManager.default.removeItem(at: base)
            } catch {
                check("export and import run without errors", false, "\(error)")
            }

            // #9: a web Block's kind can be changed by hand, and a refresh keeps it.
            do {
                let shop = model.save(url: URL(string: "https://www.example-shop.com/p/perfume-P123.html")!)
                shop.minutes = 2   // a wrong read time, as a blocked shop page once got
                // One undo group per change, as separate menu clicks would make.
                let kindUndo = UndoManager()
                kindUndo.groupsByEvent = false
                @MainActor func setKind(_ kind: BlockKind) {
                    kindUndo.beginUndoGrouping()
                    model.setKind(kind, for: shop, undo: kindUndo)
                    kindUndo.endUndoGrouping()
                }
                setKind(.product)
                check("a link can be made a product by hand", shop.kind == .product && shop.kindChosen)
                check("…and a product shows no read time", shop.minutes == nil && shop.badge == nil)
                model.apply(PageFacts(kind: .article, wordCount: 900), to: shop)
                check("…and a refresh keeps it a product without a read time", shop.kind == .product && shop.minutes == nil)
                model.apply(PageFacts(kind: .product, price: 61, currency: "EUR"), to: shop)
                check("…but still fills in a price the page has", shop.price == 61 && shop.currency == "EUR")
                setKind(.link)
                check("making it a link again drops the price", shop.kind == .link && shop.price == nil && shop.currency == nil)
                model.apply(PageFacts(kind: .product, price: 61, currency: "EUR"), to: shop)
                check("…and a refresh doesn't turn a chosen link back into a product", shop.kind == .link && shop.price == nil)
                kindUndo.undo()
                check("undo brings back the product and its price", shop.kind == .product && shop.price == 61)
                model.addNote()
                check("notes can't change kind", model.block(model.selection).map { !model.canChangeKind($0) } ?? false)
            }

            // #6, #8: a card's picture fills its own band and never resizes or covers the card.
            for (name, size) in [("very wide", CGSize(width: 2000, height: 100)), ("very tall", CGSize(width: 100, height: 1000))] {
                let result = cardPictureStaysInside(pictureSize: size)
                check("a \(name) picture keeps the card one column wide", result.width, result.detail)
                check("a \(name) picture stays above the card's text", result.inside, result.detail)
            }

            // The menu bar keeps Magpie's own menus, and Window lists Magpie once, on ⌘0.
            let menus = NSApp.mainMenu?.items.map(\.title) ?? []
            check("the menu bar has the Block, Inbox, Collection and Lucky Dip menus",
                  ["Block", "Inbox", "Collection", "Lucky Dip"].allSatisfy(menus.contains), menus.joined(separator: ", "))
            let appMenu = NSApp.mainMenu?.items.first?.submenu?.items.map(\.title) ?? []
            check("the Magpie menu has Check for Updates…", appMenu.contains("Check for Updates…"), appMenu.joined(separator: ", "))
            let windowItems = NSApp.mainMenu?.items.first { $0.title == "Window" }?.submenu?.items.filter { $0.title == "Magpie" } ?? []
            check("Window → Magpie is listed once, on ⌘0",
                  windowItems.count == 1 && windowItems.first?.keyEquivalent == "0" && windowItems.first?.keyEquivalentModifierMask == .command,
                  "\(windowItems.count) item(s), key \(windowItems.first?.keyEquivalent ?? "-")")
            let kindKeys = NSApp.mainMenu?.items.first { $0.title == "Block" }?.submenu?.items.first { $0.title == "Kind" }?.submenu?.items
                .map(\.keyEquivalentModifierMask) ?? []
            check("Block → Kind uses ⌃⌥⌘, clear of Sort By's ⌥⌘ keys",
                  kindKeys.count == 3 && kindKeys.allSatisfy { $0 == [.control, .option, .command] })

            // Closing the window (⌘W) leaves Magpie running; asking for it again (a Dock click) brings it back.
            // Last, because it closes the window. If closing quit the app, the summary below never prints.
            @MainActor func mainWindows() -> [NSWindow] { NSApp.windows.filter { $0.isVisible && $0.canBecomeMain } }
            // Earlier checks can leave a sheet open, and a window with a sheet doesn't close (for ⌘W either).
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            try? await Task.sleep(for: .milliseconds(300))
            mainWindows().first?.performClose(nil)
            try? await Task.sleep(for: .seconds(1))
            check("closing the window leaves Magpie running, with no window", mainWindows().isEmpty)
            // The Dock's own "reopen" event, sent to this process: opening the app by its bundle could
            // reach another copy of Magpie that's running (the installed one) instead.
            let reopen = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                                targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
                                                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            _ = try? reopen.sendEvent(options: [.noReply], timeout: 5)
            for _ in 0..<20 where mainWindows().isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            check("opening Magpie again (a Dock click) brings the window back", mainWindows().count == 1)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// Renders a card with a solid red picture of this size in a 240 pt column, then checks the
    /// card's width and that no red shows below the picture's band, where the text is.
    private static func cardPictureStaysInside(pictureSize: CGSize) -> (width: Bool, inside: Bool, detail: String) {
        let picture = NSImage(size: pictureSize, flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let column: CGFloat = 240, band: CGFloat = 180
        let content = CardContent(body: .visual(.image(picture)), kindLabel: "Link", title: "A card", site: "example.com",
                                  thumbHeight: band)
        let card = BlockCardView(content: content)
        let fitted = NSHostingController(rootView: card).sizeThatFits(in: CGSize(width: column, height: .infinity))
        let renderer = ImageRenderer(content: card.frame(width: column))
        renderer.scale = 1
        // Redrawn into a plain 8-bit RGBA bitmap: the renderer's own pixel format can vary.
        guard let rendered = renderer.cgImage,
              let bitmap = CGContext(data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8,
                                     bytesPerRow: rendered.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = bitmap.data?.assumingMemoryBound(to: UInt8.self)
        else { return (false, false, "the card didn't render") }
        bitmap.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        // Look along a row just under the picture band (rows run top to bottom in memory): no red allowed.
        let row = Int(band) + 4
        let red = (0..<rendered.width).contains { x in
            let pixel = bytes + row * rendered.width * 4 + x * 4
            return pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60
        }
        let widthOK = abs(fitted.width - column) < 1
        return (widthOK, !red, "card \(Int(fitted.width))×\(Int(fitted.height)), rendered \(rendered.width)×\(rendered.height)")
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
