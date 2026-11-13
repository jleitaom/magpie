import AppKit
import MagpieKit
import SwiftData
import SwiftUI

// Magpie
//   Magpie                      the app
//   APP_STORE=<file> Magpie     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> Magpie   save a PNG of every snapshot page in light and dark, then quit (scripts/snap.sh)
//   APP_SEED=1 Magpie           fill an empty /tmp store with sample blocks (scripts/snap.sh)
//   Magpie --selftest           run the self-test on a /tmp store and quit with 0 or 1 (scripts/selftest.sh)

@main
struct MagpieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())
    @ObservedObject private var menu = MenuState.shared

    var body: some Scene {
        Window("Magpie", id: "main") {
            MainView()
            .environment(model)
            .kitScene()
            .background(Ink.window)
            .background(WindowChrome())
            .frame(minWidth: Metric.windowMinimum.width, minHeight: Metric.windowMinimum.height)
        }
        .modelContainer(model.container)
        // Window → Magpie (⌘0) comes from MagpieCommands instead, with a shortcut.
        .commandsRemoved()
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Metric.windowDefault.width, height: Metric.windowDefault.height)
        .commands {
            MagpieCommands(model: model, selection: menu.selection, appearance: model.appearance,
                           viewMode: model.viewMode, canSort: model.canSortNow, sortOrder: model.order(for: model.scope),
                           canRediscover: model.canRediscoverNow,
                           pinned: model.pinnedCollections.map { PinnedItem(id: $0.uid, name: $0.name) }, dip: model.dipMenuState,
                           quickSave: model.quickSaveShortcut)
        }

        Settings {
            SettingsView()
                .environment(model)
                .kitScene()
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar. Every action is here with a shortcut. Delete, Return and arrows are
/// handled by the Gallery itself, so they keep working while typing in a field.
struct MagpieCommands: Commands {
    let model: AppModel
    let selection: UUID?
    /// Passed in, not read from the model, so the menu redraws its checkmarks when it changes.
    let appearance: AppearanceChoice
    /// Also passed in so the menus redraw: the open view, and whether M, D, → and ⌫ sort right now.
    let viewMode: ViewMode
    let canSort: Bool
    let sortOrder: BlockOrder
    let canRediscover: Bool
    /// Pinned collections for ⌘3–⌘7, passed in so the menu follows pin changes.
    let pinned: [PinnedItem]
    let dip: DipMenuState
    /// The Quick Save shortcut chosen in Settings, passed in so the menu shows it.
    let quickSave: QuickSaveShortcut
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // One Group for these two: older SwiftUI (CI's) takes at most 10 menu groups in a list.
        Group {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
            CommandGroup(before: .windowList) {
                Button("Magpie") { front() }
                    .keyboardShortcut("0")
                Divider()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Note") { front { model.addNote() } }
                .keyboardShortcut("n")
            Button("New Checklist") { front { model.addChecklist() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Add Image or File…") { chooseFiles() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Quick Save…") { model.quickSavePanel.open() }
                .keyboardShortcut(quickSave.menuShortcut)
            Button("Save Screenshot…") { model.takeScreenshot() }
                .keyboardShortcut("s", modifiers: [.control, .option])
            Button("Import Bookmarks…") { model.chooseBookmarksFile() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Export Library…") { model.chooseExportFolder() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import Magpie Export…") { model.chooseExportToImport() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") { front { model.startSearch() } }
                .keyboardShortcut("f")
            Button("Paste as New Block") { model.paste() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("Block") {
            Button("Open") { if let block = model.block(selection) { model.open(block) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(selection == nil)
            Button("Show Details") { front { model.selection = selection } }
                .disabled(selection == nil)
            Button("Quick Look") { model.quickLook(model.block(selection)) }
                .keyboardShortcut("y")
                .disabled(selection == nil)
            Button("Choose Picture…") { if let block = model.block(selection) { model.choosePicture(block) } }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model.block(selection).map { !model.canChoosePicture($0) } ?? true)
            Menu("Kind") {
                ForEach(Array(BlockKind.choosable.enumerated()), id: \.element) { index, kind in
                    Button(kind.label) {
                        if let block = model.block(selection) { model.setKind(kind, for: block, undo: NSApp.keyWindow?.undoManager) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control, .option, .command])
                    .disabled(model.block(selection).map { !model.canChangeKind($0) || $0.kind == kind } ?? true)
                }
            }
            Button(model.block(selection)?.status == .archived ? "Unarchive" : "Archive") {
                guard let block = model.block(selection) else { return }
                if block.status == .archived { model.unarchive(block) } else { model.archive(block, undo: NSApp.keyWindow?.undoManager) }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(selection == nil)
            Button("Add Tag…") {
                model.selection = selection
                model.focusTagField = true
            }
            .keyboardShortcut("t")
            .disabled(selection == nil)
            Divider()
            // ⌫ deletes in the Gallery and Journal themselves; a menu key here would catch ⌫ in text fields.
            Button("Delete") {
                if let selection { model.delete([selection], undo: NSApp.keyWindow?.undoManager) }
            }
            .disabled(selection == nil)
        }
        CommandMenu("Inbox") {
            Button("Sort Inbox") { front { model.startSorting() } }
                .keyboardShortcut("3", modifiers: [.control, .command])
            Divider()
            // Plain keys, like the action bar. Off unless Sort Inbox is showing a block with no field
            // or panel open, so typing elsewhere is never caught.
            Button("Move to Suggested") { model.sortMove(to: model.sortingBlock.flatMap(model.suggestion(for:)), undo: NSApp.keyWindow?.undoManager) }
                .keyboardShortcut("m", modifiers: [])
                .disabled(!canSort)
            Button("Rename") { model.isRenamingSortBlock = true }
                .keyboardShortcut("r", modifiers: [])
                .disabled(!canSort)
            Button("Mark Done") { model.sortDone() }
                .keyboardShortcut("d", modifiers: [])
                .disabled(!canSort)
            // One → for both Sort Inbox and Rediscover: two menu items can't share a key.
            Button("Skip") { if viewMode == .rediscover { model.rediscoverSkip() } else { model.sortSkip() } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!canSort && !canRediscover)
            Button("Delete") { model.sortDelete(undo: NSApp.keyWindow?.undoManager) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!canSort)
        }
        CommandMenu("Rediscover") {
            Button("Rediscover Old Saves") { front { model.show(.rediscover) } }
            Divider()
            Button("Keep") { model.rediscoverKeep() }
                .keyboardShortcut("k", modifiers: [])
                .disabled(!canRediscover)
            Button("Archive") { model.rediscoverArchive() }
                .keyboardShortcut("a", modifiers: [])
                .disabled(!canRediscover)
        }
        CommandMenu("Lucky Dip") {
            Button("Lucky Dip") { front { model.show(.luckyDip) } }
                .keyboardShortcut("4", modifiers: [.control, .command])
            Divider()
            Button(dip.hasPick ? "Spin Again" : "Randomize") { model.spin(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!dip.canSpin)
            Button(dip.inProgress ? "Mark as Finished" : "Start") {
                if let started = model.inProgressBlock { model.finishPick(started) } else if let pick = model.dipPick { model.startPick(pick) }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!dip.hasPick && !dip.inProgress)
            Button("Not Today") { if let pick = model.dipPick { model.notToday(pick) } }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(!dip.hasPick || dip.inProgress)
        }
        CommandMenu("Collection") {
            let open = model.openCollection
            Button("Rename Collection…") {
                // The open collection always has a tab in the top bar: rename it there.
                if let open { model.renamingCollection = open.uid }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(open == nil)
            Button("Move Up") { if let open { model.step(open, up: true) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(open == nil)
            Button("Move Down") { if let open { model.step(open, up: false) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(open == nil)
            Button("Move to Top Level") { if let open { model.place(open, .topLevel) } }
                .disabled(open?.parent == nil)
            Divider()
            Button("Delete Collection…") { model.collectionToDelete = open?.uid }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(open == nil)
        }
        // Split into small typed parts: as one expression, this group was too much for CI's
        // type checker ("unable to type-check this expression in reasonable time").
        CommandGroup(after: .sidebar) {
            viewModeItems
            Divider()
            placeItems
            Divider()
            sortByMenu
            Divider()
            appearanceMenu
            Divider()
        }
    }

    /// Gallery, Journal, Sort Inbox, Lucky Dip, Rediscover (⌃⌘1…).
    private var viewModeItems: some View {
        ForEach(ViewMode.allCases.filter(\.isAvailable)) { mode in
            Toggle(mode.title, isOn: showing(mode))
                .keyboardShortcut(KeyEquivalent(mode.shortcut), modifiers: [.control, .command])
        }
    }

    /// All, Inbox, the pinned collections (⌘1–⌘7), Archive and the Collections panel.
    @ViewBuilder private var placeItems: some View {
        Button("All Blocks") { go(to: .all) }
            .keyboardShortcut("1")
        Button("Inbox") { go(to: .inbox) }
            .keyboardShortcut("2")
        // ⌘3–⌘7: the pinned collections, in top bar order (S-032).
        ForEach(Array(pinned.enumerated()), id: \.element.id) { index, pin in
            Button(pin.name) { go(to: .collection(pin.id), gallery: viewMode != .journal) }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 3))))
        }
        Button("Archive") { go(to: .archive, gallery: true) }
            .keyboardShortcut("0", modifiers: [.control, .command])
        Button("Collections…") { front { model.showsCollections = true } }
            .keyboardShortcut("k")
    }

    /// Collection → Sort By (⌥⌘1–⌥⌘8), for the Gallery and the Journal.
    private var sortByMenu: some View {
        Menu("Sort By") {
            ForEach(Array(BlockOrder.allCases.enumerated()), id: \.element) { index, order in
                Toggle(order.title, isOn: sorted(by: order))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.option, .command])
            }
        }
        .disabled(viewMode != .gallery && viewMode != .journal)
    }

    /// Dark, Light, Match my Mac, and Switch Dark and Light (⌃⌘T).
    private var appearanceMenu: some View {
        Menu("Appearance") {
            ForEach(AppearanceChoice.allCases) { choice in
                Toggle(choice.title, isOn: looking(choice))
            }
            Divider()
            Button("Switch Dark and Light") { model.toggleAppearance() }
                .keyboardShortcut("t", modifiers: [.control, .command])
        }
    }

    private func showing(_ mode: ViewMode) -> Binding<Bool> {
        Binding(get: { viewMode == mode }, set: { on in if on { front { model.show(mode) } } })
    }

    private func sorted(by order: BlockOrder) -> Binding<Bool> {
        Binding(get: { sortOrder == order }, set: { on in if on { model.setOrder(order, for: model.scope) } })
    }

    private func looking(_ choice: AppearanceChoice) -> Binding<Bool> {
        Binding(get: { appearance == choice }, set: { on in if on { model.appearance = choice } })
    }

    /// Opens a place (All, Inbox, a collection, Archive), bringing the window back first.
    private func go(to scope: Scope, gallery: Bool = false) {
        front {
            model.scope = scope
            if gallery { model.show(.gallery) }
        }
    }

    /// Brings the main window back (after ⌘W closed it), then does the action there.
    private func front(_ action: () -> Void = {}) {
        openWindow(id: "main")
        action()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { model.save(.file($0)) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared // starts Sparkle's scheduled checks
        // Remember the app you were in, to give it the focus back after a quick Dock drop.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { AppDelegate.lastOtherApp = app }
            }
        }
    }

    /// The last app other than Magpie that was in front.
    static var lastOtherApp: NSRunningApplication?

    /// ⌘W closes the window, not the app: Quick Save, Dock drops and the Dock badge keep working,
    /// and clicking the Dock icon or Window → Magpie (⌘0) brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dropped on the Dock icon before the model was ready (Magpie was launched by the drop).
    static var pendingURLs: [URL] = []
    /// When Magpie last came to the front, to tell a quick drop from waiting on the icon.
    private var activeSince: Date?

    func applicationDidBecomeActive(_ notification: Notification) {
        activeSince = .now
        Self.trace("becomeActive")
        AppModel.current?.refreshDockBadge()   // a new day may have started
    }
    func applicationDidResignActive(_ notification: Notification) { activeSince = nil; Self.trace("resignActive") }

    /// APP_TRACE=<file>: logs activation and Dock drops with timestamps, for checking the quick-drop timing.
    static func trace(_ what: String) {
        guard let path = ProcessInfo.processInfo.environment["APP_TRACE"] else { return }
        let line = "\(Date.now.timeIntervalSince1970) \(what) lastOther=\(lastOtherApp?.localizedName ?? "-")\n"
        if let handle = FileHandle(forWritingAtPath: path) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// Links, images and files dropped on the Dock icon (S-041). A quick drop saves to the Inbox,
    /// shows "Saved to Inbox" by the Dock and leaves you where you were. Holding the item on the
    /// icon until the Dock brings Magpie forward opens Magpie instead.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model = AppModel.current else {
            Self.pendingURLs += urls   // launched by the drop: saved once the library is ready, then hidden
            return
        }
        let stepBack = !NSApp.isActive || DockDrop.shouldStepBack(activeSince: activeSince, wasRunning: true, now: .now)
        Self.trace("open isActive=\(NSApp.isActive) activeFor=\(activeSince.map { Date.now.timeIntervalSince($0) } ?? -1) stepBack=\(stepBack)")
        let saved = model.receive(urls, quietly: stepBack)
        guard stepBack, !saved.isEmpty else { return }
        DropHUD.show(model.receiveMessage)
        Self.stepBack()
    }

    /// Hides Magpie once the Dock's activation has finished, and gives the focus back to the app you were in.
    static func stepBack() {
        let previous = lastOtherApp
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            NSApp.hide(nil)
            previous?.activate()
        }
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Magpie → Check for Updates…, greyed out while a check runs or in builds without updates.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}

/// Where the data lives: ~/Library/Application Support/Magpie/Library.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "Magpie", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A new file name: the template's test store (Magpie.store) had a different schema.
        return dir.appending(path: "Library.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Block.self, BlockCollection.self, DayActivity.self, Tag.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}

extension QuickSaveShortcut {
    /// The same keys for the File menu, or none when the shortcut is Off.
    var menuShortcut: KeyboardShortcut? {
        switch self {
        case .controlOptionSpace: KeyboardShortcut(.space, modifiers: [.control, .option])
        case .controlOptionM: KeyboardShortcut("m", modifiers: [.control, .option])
        case .optionCommandSpace: KeyboardShortcut(.space, modifiers: [.option, .command])
        case .off: nil
        }
    }
}

struct PinnedItem: Equatable {
    let id: UUID
    let name: String
}
