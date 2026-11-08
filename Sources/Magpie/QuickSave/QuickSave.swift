import AppKit
import MagpieKit
import SwiftUI

/// What Quick Save is about to save, and where it came from.
struct QuickSaveDraft: Equatable {
    enum Content: Equatable {
        case web(URL)
        case text(String)
        case image(Data)
        case nothing
    }

    var content: Content
    var title: String
    /// "From Safari", "From the clipboard", or why Safari couldn't be read.
    var source: String
}

/// Reads the front Safari tab, or the clipboard (S-030).
enum QuickSaveSource {
    /// Safari's front tab when Safari is the front app, else the clipboard. Safari is read with
    /// AppleScript; the first time macOS asks for permission, and if it's refused the clipboard is used.
    static func capture(frontApp: NSRunningApplication?) async -> QuickSaveDraft {
        if frontApp?.bundleIdentifier == "com.apple.Safari" {
            switch await safariTab() {
            case .success(let tab):
                return QuickSaveDraft(content: .web(tab.url), title: tab.title, source: "From Safari")
            case .failure(let reason):
                var draft = clipboard()
                draft.source = reason.reason + " Saving the clipboard instead."
                return draft
            }
        }
        return clipboard()
    }

    static func clipboard(_ pasteboard: NSPasteboard = .general) -> QuickSaveDraft {
        switch AppModel.read(pasteboard).first {
        case .web(let url)?:
            return QuickSaveDraft(content: .web(url), title: Links.placeName(url) ?? Links.siteName(url), source: "From the clipboard")
        case .file(let url)?:
            return QuickSaveDraft(content: .web(url), title: url.deletingPathExtension().lastPathComponent, source: "From the clipboard")
        case .image(let data, _)?:
            return QuickSaveDraft(content: .image(data), title: "Image", source: "From the clipboard")
        case .text(let text)?:
            if let url = Links.parse(text) {
                return QuickSaveDraft(content: .web(url), title: Links.siteName(url), source: "From the clipboard")
            }
            return QuickSaveDraft(content: .text(text), title: Titles.firstLine(text), source: "From the clipboard")
        case nil:
            return QuickSaveDraft(content: .nothing, title: "", source: "The clipboard is empty.")
        }
    }

    private struct Tab: Sendable { let url: URL; let title: String }
    private struct Refused: Error { let reason: String }

    private static func safariTab() async -> Result<Tab, Refused> {
        await Task.detached {
            let source = """
            tell application "Safari"
                if (count of windows) is 0 then return ""
                set theTab to current tab of front window
                return (URL of theTab) & linefeed & (name of theTab)
            end tell
            """
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue ?? ""
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                return .failure(Refused(reason: code == -1743 ? "Magpie isn't allowed to read Safari (System Settings → Privacy & Security → Automation)."
                                                              : "Couldn't read Safari's tab."))
            }
            let lines = output.split(separator: "\n", maxSplits: 1).map(String.init)
            guard let first = lines.first, let url = URL(string: first), url.scheme?.hasPrefix("http") == true else {
                return .failure(Refused(reason: "Safari has no web page open."))
            }
            return .success(Tab(url: url, title: lines.count > 1 ? lines[1] : Links.siteName(url)))
        }.value
    }
}

/// The floating Quick Save panel. It takes the keyboard without bringing Magpie's window
/// forward, so you stay in Safari. Return saves, Escape cancels.
@MainActor
final class QuickSavePanel {
    private var panel: NSPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var window: NSWindow? { panel }

    /// The shortcut: read the front tab or clipboard, then show the panel.
    func open() {
        let front = NSWorkspace.shared.frontmostApplication
        Task {
            let draft = await QuickSaveSource.capture(frontApp: front)
            show(draft)
        }
    }

    func show(_ draft: QuickSaveDraft) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let view = QuickSaveView(draft: draft, onSave: { [weak self] edited in self?.save(edited) },
                                 onCancel: { [weak self] in self?.close() })
            .environment(model)
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: Metric.quickSaveWidth, height: 320))
        // A third of the way down the screen with the mouse, like Spotlight.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.maxY - visible.height / 3 - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    struct Edited {
        var draft: QuickSaveDraft
        var title: String
        var collection: UUID?
        var tags: String
        var note: String
    }

    /// Saves, files and tags the block, then closes.
    func save(_ edited: Edited) {
        model.quickSave(edited)
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: Metric.quickSaveWidth, height: 320),
                             styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// A borderless panel that can still take typing.
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

/// The panel's content: title, where it came from, collection, tags and a note.
struct QuickSaveView: View {
    let draft: QuickSaveDraft
    let onSave: (QuickSavePanel.Edited) -> Void
    let onCancel: () -> Void
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var collection: UUID?
    @State private var tags = ""
    @State private var note = ""
    @FocusState private var focus: Field?

    enum Field { case title, tags, note }

    var body: some View {
        let canSave = draft.content != .nothing
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Quick Save").kitType(.heading).foregroundStyle(Ink.text)
                Spacer()
                Text(draft.source).kitType(.meta).foregroundStyle(draft.source.hasPrefix("From") ? Ink.secondary : Ink.noteLabel)
                    .lineLimit(2).multilineTextAlignment(.trailing)
            }
            TextField("Title", text: $title).kitField().focused($focus, equals: .title)
            if case .web(let url) = draft.content {
                Text(url.absoluteString).kitType(.meta).foregroundStyle(Ink.accentText).lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: Space.sm) {
                Text("Save to").kitType(.meta).foregroundStyle(Ink.secondary)
                Menu(model.collection(collection)?.name ?? "Inbox") {
                    Button("Inbox") { collection = nil }
                    Divider()
                    ForEach(model.collectionTree, id: \.collection.uid) { row in
                        Button(String(repeating: "   ", count: row.depth) + row.collection.name) { collection = row.collection.uid }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.kit(.secondary))
                .fixedSize()
            }
            TextField("Tags, separated by commas", text: $tags).kitField().focused($focus, equals: .tags)
            TextField("Why are you saving this?", text: $note, axis: .vertical).lineLimit(2...4)
                .kitField().focused($focus, equals: .note)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.kit(.ghost))
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(QuickSavePanel.Edited(draft: draft, title: title, collection: collection, tags: tags, note: note))
                }
                .buttonStyle(.kit())
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(Space.xl)
        .frame(width: Metric.quickSaveWidth)
        .background(RoundedRectangle(cornerRadius: Metric.radiusPanel, style: .continuous).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: Metric.radiusPanel, style: .continuous).strokeBorder(Ink.hairline))
        .kitScene()
        .onAppear {
            title = draft.title
            focus = .title
        }
        .onExitCommand(perform: onCancel)
    }
}
