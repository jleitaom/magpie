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
