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
                    if page == .quickSave {
                        if let panel = model.quickSavePanel.window { capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: panel) }
                        model.quickSavePanel.close()
                    } else if page.hasPopover {
                        // Let the previous popover finish closing, or the new one won't open.
                        try? await Task.sleep(for: .seconds(0.8))
                        page.openPopover(in: model)
                    }
                    try? await Task.sleep(for: .seconds(1.2))
                    if page == .quickSave {
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
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
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

    case all, inbox, collection, details, empty, collections, newBlock, rename, renameTab, sortInbox, inboxZero, luckyDip, luckyDipPick, luckyDipStarted, tag, journal, sortMenu, rediscover, archive, search, shopping, quickSave

    /// Pages that open a popover. Their snapshot is the popover alone.
    var hasPopover: Bool { self == .collections || self == .newBlock || self == .rename || self == .sortMenu }

    func show(in model: AppModel) {
        model.endSearch()
        model.viewMode = .gallery
        // Lucky Dip pages leave no pick or started block behind for the next page.
        model.todayIfAny?.pickUID = nil
        model.todayIfAny?.spins = 0
        if let (uid, status) = Self.startedOriginal, let block = model.block(uid) { block.status = status }
        Self.startedOriginal = nil
        model.selection = nil
        model.renamingCollection = nil
        model.showsCollections = false
        model.showsNewMenu = false
        model.showsSortMenu = false
        switch self {
        case .all: model.scope = .all
        case .inbox: model.scope = .inbox
        case .collection: model.scope = model.pinnedCollections.dropFirst().first.map { .collection($0.uid) } ?? .all
        case .details:
            model.scope = .all
            let newest = (try? model.context.fetch(FetchDescriptor<Block>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?
                .first { $0.thumbnail != nil }
            model.selection = newest?.uid
        case .empty:
            model.scope = model.collections.first { ($0.blocks ?? []).isEmpty }.map { .collection($0.uid) } ?? .all
        case .sortInbox:
            model.scope = .all
            model.startSorting()
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
        case .quickSave:
            model.scope = .all
            model.quickSavePanel.show(QuickSaveDraft(content: .web(URL(string: "https://www.dezeen.com/lisbon-guide")!),
                                                     title: "An architect’s guide to Lisbon", source: "From Safari"))
        case .shopping:
            model.scope = model.collections.first { $0.name == "Shopping" }.map { .collection($0.uid) } ?? .all
        case .tag:
            model.scope = model.tags.first { $0.name == "jazz" }.map { .tag($0.uid) } ?? .all
        case .luckyDip:
            model.dipPile = .read
            model.viewMode = .luckyDip
        case .luckyDipPick, .luckyDipStarted:
            model.dipPile = .watch
            model.viewMode = .luckyDip
            if let pick = model.pileBlocks(.watch).first {
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
