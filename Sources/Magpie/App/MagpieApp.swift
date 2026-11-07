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
        .commands { MagpieCommands(model: model, selection: menu.selection, appearance: model.appearance) }

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
            Button("Paste as New Block") { model.paste() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("Block") {
            Button("Open") { if let block = model.block(selection) { model.open(block) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(selection == nil)
            Button("Show Details") { model.selection = selection }
                .disabled(selection == nil)
            Divider()
            Button("Delete") {
                if let selection { model.delete([selection], undo: NSApp.keyWindow?.undoManager) }
            }
            .disabled(selection == nil)
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
            Button("All Blocks") { model.scope = .all }
                .keyboardShortcut("1")
            Button("Inbox") { model.scope = .inbox }
                .keyboardShortcut("2")
            Button("Collections…") { model.showsCollections = true }
                .keyboardShortcut("k")
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
            return try ModelContainer(for: Block.self, BlockCollection.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
