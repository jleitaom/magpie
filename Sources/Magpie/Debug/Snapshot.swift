import AppKit
import IOKit.pwr_mgt
import SwiftData
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots build/Magpie.app/Contents/MacOS/Magpie
/// writes <page>-light.png and <page>-dark.png for every SnapshotPage, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// APP_SNAPSHOT_PAGES=all,details limits the pages (SnapshotPage). Add "settings" to include Settings.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SnapshotPage.allCases where only?.contains(page.rawValue) ?? true {
                    page.show(in: model)
                    if page.hasPopover {
                        // Let the previous popover finish closing, or the new one won't open.
                        try? await Task.sleep(for: .seconds(0.8))
                        page.openPopover(in: model)
                    }
                    if page == .afterDelete, let doomed = model.selection {
                        // Delete the selected card, the way ⌫ does, then capture the Gallery right after.
                        try? await Task.sleep(for: .seconds(0.8))
                        model.delete([doomed], undo: nil)
                        try? await Task.sleep(for: .milliseconds(150))
                        capture(to: "\(dir)/\(page.rawValue)-mid-\(mode).png")
                    }
                    try? await Task.sleep(for: .seconds(1.2))
                    if page == .dropHUD {
                        if let hud = DropHUD.window { capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: hud) }
                    } else if page == .importSheet || page == .pictureChooser {
                        let sheet = NSApp.windows.compactMap(\.attachedSheet).first ?? NSApp.windows.first { $0.isSheet && $0.isVisible }
                        if let sheet { capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: sheet) }
                        else { print("SNAPSHOT no sheet: \(NSApp.windows.map { "\(type(of: $0)) visible:\($0.isVisible) sheet:\($0.isSheet)" })") }
                        model.bookmarkImport = nil
                        model.pictureChoice = nil
                        try? await Task.sleep(for: .seconds(0.6))
                    } else if page == .quickSave {
                        if let panel = model.quickSavePanel.window { capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: panel) }
                        model.quickSavePanel.close()
                    } else if page.hasPopover {
                        // A popover is a window of its own: capture just that window.
                        let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
                        if let popover { capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: popover) }
                        else { print("SNAPSHOT no popover for \(page.rawValue)") }
                    } else {
                        capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                    }
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        // Not a panel: the Dock drop message can still be up from its own page.
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && !($0 is NSPanel) }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}

/// The screens snapshot mode captures. Add a case for every new screen or state worth checking.
enum SnapshotPage: String, CaseIterable {
    /// The block the luckyDipStarted page marked In progress, and its status before, to put back.
    @MainActor static var startedOriginal: (UUID, BlockStatus)?
    /// Blocks the empty Archive page took out of the Archive, to put back for the next page.
    @MainActor static var unarchived: [(UUID, BlockStatus)] = []

    case all, inbox, collection, details, detailsNote, detailsPlace, empty, collections, newBlock, rename, renameTab, sortInbox, inboxZero, luckyDip, luckyDipPick, luckyDipStarted, tag, journal, sortMenu, rediscover, archive, search, shopping, quickSave, importSheet, dropHUD, sortRename, afterDelete, firstLaunch, emptyArchive, pictureChooser

    /// Pages that open a popover. Their snapshot is the popover alone.
    var hasPopover: Bool { self == .collections || self == .newBlock || self == .rename || self == .sortMenu }

    func show(in model: AppModel) {
        model.endSearch()
        model.snapshotEmptyLibrary = self == .firstLaunch
        model.viewMode = .gallery
        // Lucky Dip pages leave no pick or started block behind for the next page.
        model.todayIfAny?.pickUID = nil
        model.todayIfAny?.spins = 0
        if let (uid, status) = Self.startedOriginal, let block = model.block(uid) { block.status = status }
        Self.startedOriginal = nil
        // The empty Archive page puts archived blocks back for a moment; archive them again.
        for (uid, status) in Self.unarchived { model.block(uid)?.status = status }
        Self.unarchived = []
        model.selection = nil
        model.renamingCollection = nil
        model.showsCollections = false
        model.showsNewMenu = false
        model.showsSortMenu = false
        switch self {
        case .all: model.scope = .all
        case .inbox: model.scope = .inbox
        case .collection: model.scope = model.pinnedCollections.dropFirst().first.map { .collection($0.uid) } ?? .all
        case .detailsNote, .detailsPlace:
            // A block with no picture, and a place with its map: the close button's two other homes.
            model.scope = .all
            let kind: BlockKind = self == .detailsNote ? .note : .place
            model.selection = (try? model.context.fetch(FetchDescriptor<Block>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?
                .first { $0.kind == kind && $0.status != .archived }?.uid
        case .details:
            model.scope = .all
            let newest = (try? model.context.fetch(FetchDescriptor<Block>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?
                .first { $0.thumbnail != nil }
            model.selection = newest?.uid
        case .empty:
            model.scope = model.collections.first { ($0.blocks ?? []).isEmpty }.map { .collection($0.uid) } ?? .all
        case .sortInbox, .sortRename:
            model.scope = .all
            model.startSorting()
            model.isRenamingSortBlock = self == .sortRename
        case .journal:
            model.scope = .all
            model.viewMode = .journal
            let third = model.ordered(model.blocks(in: .all, from: (try? model.context.fetch(FetchDescriptor<Block>())) ?? []), in: .all).dropFirst(2).first
            model.selection = third?.uid
        case .sortMenu:
            model.scope = .all
        case .rediscover:
            model.scope = .all
            model.startRediscover()
        case .archive:
            model.scope = .archive
        case .search:
            model.scope = .all
            model.startSearch()
            model.searchQuery = "lisbon"
        case .firstLaunch:
            model.scope = .all
        case .emptyArchive:
            model.scope = .archive
            // The sample library's archived blocks, put back for this page, so the Archive is empty.
            for block in model.blocks(in: .archive, from: (try? model.context.fetch(FetchDescriptor<Block>())) ?? []) {
                Self.unarchived.append((block.uid, block.status))
                block.status = .kept
            }
        case .afterDelete:
            model.scope = .all
            let shown = model.ordered(model.blocks(in: .all, from: (try? model.context.fetch(FetchDescriptor<Block>())) ?? []), in: .all)
            model.selection = shown.dropFirst(1).first?.uid
        case .dropHUD:
            model.scope = .all
            DropHUD.show("Saved to Inbox")
        case .pictureChooser:
            // A product with the other sample pictures standing in for its page's pictures.
            model.scope = .all
            let blocks = model.blocks(in: .all, from: (try? model.context.fetch(FetchDescriptor<Block>())) ?? [])
            if let lamp = blocks.first(where: { $0.title.hasPrefix("Desk lamp") }) {
                let others = blocks.filter { $0.uid != lamp.uid && $0.thumbnail != nil }.prefix(7)
                let choices = others.compactMap { other in other.thumbnail.map { ProcessedImage(jpeg: $0, aspect: other.thumbnailAspect, color: nil) } }
                model.pictureChoice = PictureChoice(uid: lamp.uid, choices: (lamp.thumbnail.map { [ProcessedImage(jpeg: $0, aspect: 1, color: nil)] } ?? []) + choices)
            }
        case .importSheet:
            model.scope = .all
            model.previewBookmarks(Snapshot.sampleBookmarks, file: "Safari Bookmarks.html")
        case .quickSave:
            model.scope = .all
            model.quickSavePanel.show(QuickSaveDraft(content: .web(URL(string: "https://www.dezeen.com/lisbon-guide")!),
                                                     title: "An architect’s guide to Lisbon", source: "From Safari"))
        case .shopping:
            model.scope = model.collections.first { $0.name == "Shopping" }.map { .collection($0.uid) } ?? .all
        case .tag:
            model.scope = model.tags.first { $0.name == "jazz" }.map { .tag($0.uid) } ?? .all
        case .luckyDip:
            model.dipCollection = nil
            model.viewMode = .luckyDip
        case .luckyDipPick, .luckyDipStarted:
            let watchLater = model.collections.first { $0.name == "Watch later" }
            model.dipCollection = watchLater?.uid
            model.viewMode = .luckyDip
            if let pick = model.dipBlocks(from: watchLater?.uid).first {
                if self == .luckyDipStarted {
                    Self.startedOriginal = (pick.uid, pick.status)
                    pick.status = .inProgress
                } else {
                    model.today.pickUID = pick.uid
                    model.today.spins = 1
                }
            }
        case .inboxZero:
            model.scope = .all
            model.viewMode = .sortInbox
            model.sortSession = .finished(kept: 5, done: 2, deleted: 1)
        case .renameTab:
            let first = model.pinnedCollections.first
            model.scope = first.map { .collection($0.uid) } ?? .all
            model.renamingCollection = first?.uid
        case .collections, .newBlock, .rename:
            model.scope = .all
            model.renamingCollection = nil
        }
    }

    func openPopover(in model: AppModel) {
        if self == .rename { model.renamingCollection = model.collectionTree.first?.collection.uid }
        model.showsCollections = self == .collections || self == .rename
        model.showsNewMenu = self == .newBlock
        model.showsSortMenu = self == .sortMenu
    }
}

extension Snapshot {
    /// A small Safari export for the import sheet's snapshot.
    static let sampleBookmarks = """
    <DL><p>
      <DT><H3>Favorites</H3>
      <DL><p>
        <DT><A HREF="https://news.ycombinator.com">Hacker News</A>
        <DT><A HREF="https://www.inkandswitch.com/local-first/">Local-first software</A>
      </DL><p>
      <DT><H3>Bookmarks Menu</H3>
      <DL><p>
        <DT><H3>Recipes</H3>
        <DL><p>
          <DT><A HREF="https://www.seriouseats.com/a">Neapolitan dough</A><DT><A HREF="https://www.seriouseats.com/b">Bacalhau à Brás</A>
          <DT><A HREF="https://www.seriouseats.com/c">Arroz de pato</A>
        </DL><p>
        <DT><H3>Design</H3>
        <DL><p>
          <DT><A HREF="https://example.com/1">Type specimen</A><DT><A HREF="https://example.com/2">Grid systems</A>
        </DL><p>
      </DL><p>
      <DT><A HREF="https://example.com/loose">Reading list item</A>
    </DL><p>
    """
}
