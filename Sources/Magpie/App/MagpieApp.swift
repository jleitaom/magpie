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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Metric.windowDefault.width, height: Metric.windowDefault.height)
        .commands {
            MagpieCommands(model: model, selection: menu.selection, appearance: model.appearance,
                           viewMode: model.viewMode, canSort: model.canSortNow, sortOrder: model.order(for: model.scope),
                           canRediscover: model.canRediscoverNow, dip: model.dipMenuState)
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
    let dip: DipMenuState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { model.addNote() }
                .keyboardShortcut("n")
            Button("New Checklist") { model.addChecklist() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Add Image or File…") { chooseFiles() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") { model.startSearch() }
                .keyboardShortcut("f")
            Button("Paste as New Block") { model.paste() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("Block") {
            Button("Open") { if let block = model.block(selection) { model.open(block) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(selection == nil)
            Button("Show Details") { model.selection = selection }
                .disabled(selection == nil)
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
            Button("Delete") {
                if let selection { model.delete([selection], undo: NSApp.keyWindow?.undoManager) }
            }
            .disabled(selection == nil)
        }
        CommandMenu("Inbox") {
            Button("Sort Inbox") { model.startSorting() }
                .keyboardShortcut("3", modifiers: [.control, .command])
            Divider()
            // Plain keys, like the action bar. Off unless Sort Inbox is showing a block with no field
            // or panel open, so typing elsewhere is never caught.
            Button("Move to Suggested") { model.sortMove(to: model.sortingBlock.flatMap(model.suggestion(for:)), undo: NSApp.keyWindow?.undoManager) }
                .keyboardShortcut("m", modifiers: [])
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
            Button("Rediscover Old Saves") { model.show(.rediscover) }
            Divider()
            Button("Keep") { model.rediscoverKeep() }
                .keyboardShortcut("k", modifiers: [])
                .disabled(!canRediscover)
            Button("Archive") { model.rediscoverArchive() }
                .keyboardShortcut("a", modifiers: [])
                .disabled(!canRediscover)
        }
        CommandMenu("Lucky Dip") {
            Button("Lucky Dip") { model.show(.luckyDip) }
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
        CommandGroup(after: .sidebar) {
            ForEach(ViewMode.allCases.filter(\.isAvailable)) { mode in
                Toggle(mode.title, isOn: Binding(get: { viewMode == mode }, set: { if $0 { model.show(mode) } }))
                    .keyboardShortcut(KeyEquivalent(mode.shortcut), modifiers: [.control, .command])
            }
            Divider()
            Button("All Blocks") { model.scope = .all }
                .keyboardShortcut("1")
            Button("Inbox") { model.scope = .inbox }
                .keyboardShortcut("2")
            Button("Archive") { model.scope = .archive; model.show(.gallery) }
                .keyboardShortcut("0", modifiers: [.control, .command])
            Button("Collections…") { model.showsCollections = true }
                .keyboardShortcut("k")
            Divider()
            Menu("Sort By") {
                ForEach(Array(BlockOrder.allCases.enumerated()), id: \.element) { index, order in
                    Toggle(order.title, isOn: Binding(get: { sortOrder == order }, set: { if $0 { model.setOrder(order, for: model.scope) } }))
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.option, .command])
                }
            }
            .disabled(viewMode != .gallery && viewMode != .journal)
            Divider()
            Menu("Appearance") {
                ForEach(AppearanceChoice.allCases) { choice in
                    Toggle(choice.title, isOn: Binding(
                        get: { appearance == choice },
                        set: { if $0 { model.appearance = choice } }
                    ))
                }
                Divider()
                Button("Switch Dark and Light") { model.toggleAppearance() }
                    .keyboardShortcut("t", modifiers: [.control, .command])
            }
            Divider()
        }
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
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
