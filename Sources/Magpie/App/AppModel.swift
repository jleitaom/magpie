import AppKit
import MagpieKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What the Gallery shows.
enum Scope: Hashable {
    case all, inbox
    case collection(UUID)
}

/// The view switcher's modes. Gallery and Sort Inbox exist so far (notes/PLAN.md).
enum ViewMode: String, CaseIterable, Identifiable {
    case gallery, journal, sortInbox, luckyDip
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .journal: "Journal"
        case .sortInbox: "Sort Inbox"
        case .luckyDip: "Lucky Dip"
        }
    }

    var icon: KitIcon {
        switch self {
        case .gallery: .gallery
        case .journal: .journal
        case .sortInbox: .sortInbox
        case .luckyDip: .luckyDip
        }
    }

    var isAvailable: Bool { self == .gallery || self == .sortInbox }

    /// ⌃⌘1 to ⌃⌘4, in the View menu.
    var shortcut: Character {
        switch self {
        case .gallery: "1"
        case .journal: "2"
        case .sortInbox: "3"
        case .luckyDip: "4"
        }
    }

    var shortcutLabel: String { "⌃⌘\(shortcut)" }
}

/// Dark by default, like the mockup; Light or "Match my Mac" in Settings.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Match my Mac"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }
}

/// Something dropped or pasted, read into plain values.
enum Incoming: Sendable {
    case web(URL)
    case file(URL)
    case image(Data, name: String?)
    case text(String)
}

/// App-wide state and every action. Views read it and call it; they never change the data directly.
@Observable
final class AppModel {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    var scope: Scope = .all
    var viewMode: ViewMode = .gallery
    var selection: UUID? { didSet { MenuState.shared.update(selection) } }
    var showsCollections = false
    var showsNewMenu = false
    /// The current Sort Inbox run (S-060).
    var sortSession = SortSession(inbox: [])
    /// The collection whose name is being edited in the Collections panel.
    var renamingCollection: UUID?
    /// The collection waiting for the delete confirmation.
    var collectionToDelete: UUID?
    var isDropTargeted = false
    var toast: String?
    var settingsTab: SettingsTab = .general

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var enriching: Set<UUID> = []

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Appearance

    /// Saved in the app's preferences. A stored property, so the View menu's checkmarks follow it.
    var appearance: AppearanceChoice = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .dark {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    /// Flips between Dark and Light (⌃⌘T). From "Match my Mac", it picks the opposite of what
    /// the Mac shows now.
    func toggleAppearance() {
        let isDark = switch appearance {
        case .dark: true
        case .light: false
        case .system: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        appearance = isDark ? .light : .dark
    }

    /// Called once the window is up: retries previews that didn't finish last time.
    func start() {
        applyAppearance()
        refreshStreak()
        let pending = EnrichState.pending.rawValue
        let stuck = (try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.enrichRaw == pending }))) ?? []
        for block in stuck { enrich(block) }
    }

    // MARK: Lookups

    func block(_ uid: UUID?) -> Block? {
        guard let uid else { return nil }
        return try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.uid == uid })).first
    }

    func collection(_ uid: UUID?) -> BlockCollection? {
        guard let uid else { return nil }
        return try? context.fetch(FetchDescriptor<BlockCollection>(predicate: #Predicate { $0.uid == uid })).first
    }

    var collections: [BlockCollection] {
        (try? context.fetch(FetchDescriptor<BlockCollection>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    /// The blocks a scope shows, newest first.
    func blocks(in scope: Scope, from all: [Block]) -> [Block] {
        switch scope {
        case .all: all.filter { $0.status != .archived }
        case .inbox: all.filter { $0.status == .inbox }
        case .collection(let uid): all.filter { $0.collection?.uid == uid && $0.status != .archived }
        }
    }

    // MARK: Saving

    /// Where new blocks go: into the open collection, or the Inbox.
    private func place(_ block: Block) {
        if case .collection(let uid) = scope, let target = collection(uid) {
            block.collection = target
            block.status = .kept
        } else {
            block.status = .inbox
        }
        context.insert(block)
        today.saved += 1
        save()
    }

    /// Saves a web link. A link that's already saved moves to the top instead of being saved twice.
    @discardableResult
    func save(url: URL) -> Block {
        let normalized = Links.normalize(url)
        if let existing = try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.normalizedURL == normalized })).first {
            existing.createdAt = .now
            if existing.status == .archived { existing.status = .inbox }
            save()
            flash("Already saved — moved to the top")
            return existing
        }
        let kind: BlockKind = switch Links.kind(url) {
        case .video: .video
        case .place: .place
        case .image: .image
        case .link: .link
        }
        let block = Block(kind: kind, title: Links.siteName(url))
        block.urlString = url.absoluteString
        block.normalizedURL = normalized
        block.siteName = Links.siteName(url)
        block.enrich = .pending
        place(block)
        enrich(block)
        return block
    }

    func save(_ incoming: Incoming) {
        switch incoming {
        case .web(let url):
            save(url: url)
        case .file(let url):
            if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
               let data = try? Data(contentsOf: url) {
                saveImage(data, name: url.deletingPathExtension().lastPathComponent)
            } else {
                let block = Block(kind: .file, title: url.deletingPathExtension().lastPathComponent)
                block.urlString = url.absoluteString
                block.siteName = url.pathExtension.uppercased().isEmpty ? "File" : url.pathExtension.uppercased() + " file"
                place(block)
            }
        case .image(let data, let name):
            saveImage(data, name: name)
        case .text(let text):
            if let url = Links.parse(text) {
                save(url: url)
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let block = Block(kind: .note, title: Titles.firstLine(text))
                block.bodyText = text
                block.siteName = "Note"
                place(block)
            }
        }
    }

    func saveImage(_ data: Data, name: String?) {
        let block = Block(kind: .image, title: name ?? "Image")
        block.siteName = "Image"
        block.enrich = .pending
        place(block)
        let uid = block.uid
        Task {
            let processed = await Ingest.process(data)
            guard let block = self.block(uid) else { return }
            self.apply(processed, to: block)
            block.enrich = processed == nil ? .failed : .done
            self.save()
        }
    }

    func addNote() {
        let block = Block(kind: .note, title: "New note")
        block.siteName = "Note"
        place(block)
        selection = block.uid
    }

    func addChecklist() {
        let block = Block(kind: .checklist, title: "New checklist")
        block.siteName = "Checklist"
        block.checklist = [ChecklistItem(text: "")]
        place(block)
        selection = block.uid
    }

    /// Reads whatever is on the clipboard: links, files, images, or text.
    func paste(from pasteboard: NSPasteboard = .general) {
        let items = Self.read(pasteboard)
        guard !items.isEmpty else { flash("Nothing to paste"); return }
        items.forEach(save)
        if items.count > 1 { flash("Saved \(items.count) blocks") }
    }

    static func read(_ pasteboard: NSPasteboard) -> [Incoming] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls.map { $0.isFileURL ? .file($0) : .web($0) }
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return [.image(data, name: nil)]
        }
        if let text = pasteboard.string(forType: .string) {
            return [.text(text)]
        }
        return []
    }

    // MARK: Previews

    private func enrich(_ block: Block) {
        guard let url = block.url, !url.isFileURL, !enriching.contains(block.uid) else { return }
        let uid = block.uid
        enriching.insert(uid)
        Task {
            defer { enriching.remove(uid) }
            let preview = await Ingest.fetchPreview(url)
            var processed: ProcessedImage?
            if let data = preview?.imageData { processed = await Ingest.process(data) }
            guard let block = self.block(uid) else { return }   // deleted meanwhile
            if let title = preview?.title.map(Titles.clean), !title.isEmpty, block.title == block.siteName {
                block.title = title
            }
            apply(processed, to: block)
            block.enrich = preview == nil ? .failed : .done
            save()
        }
    }

    private func apply(_ processed: ProcessedImage?, to block: Block) {
        guard let processed else { return }
        block.thumbnail = processed.jpeg
        block.thumbnailAspect = processed.aspect
        block.colorHex = processed.color.map(Int.init)
    }

    // MARK: Changing blocks

    func open(_ block: Block) {
        if let url = block.url {
            block.openedAt = .now
            save()
            NSWorkspace.shared.open(url)
        } else {
            selection = block.uid
        }
    }

    func move(_ block: Block, to target: BlockCollection?, undo: UndoManager?) {
        let before = block.collection
        let beforeStatus = block.status
        block.collection = target
        block.status = target == nil ? .inbox : .kept
        noteInboxZero()
        save()
        let uid = block.uid
        undo?.registerUndo(withTarget: self) { model in
            guard let block = model.block(uid) else { return }
            model.move(block, to: before, undo: undo)
            block.status = beforeStatus
        }
        undo?.setActionName("Move")
        flash(target.map { "Moved to \($0.name)" } ?? "Moved to Inbox")
    }

    func delete(_ uids: [UUID], undo: UndoManager?) {
        let doomed = uids.compactMap(block)
        guard !doomed.isEmpty else { return }
        let copies = doomed.map(BlockCopy.init)
        doomed.forEach(context.delete)
        if let selection, uids.contains(selection) { self.selection = nil }
        noteInboxZero()
        save()
        undo?.registerUndo(withTarget: self) { model in model.restore(copies, undo: undo) }
        undo?.setActionName(doomed.count == 1 ? "Delete Block" : "Delete Blocks")
    }

    private func restore(_ copies: [BlockCopy], undo: UndoManager?) {
        for copy in copies { context.insert(copy.makeBlock(in: self)) }
        save()
        undo?.registerUndo(withTarget: self) { model in model.delete(copies.map(\.uid), undo: undo) }
    }

    // MARK: Collections

    @discardableResult
    func createCollection(named name: String, colorHex: Int? = nil) -> BlockCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = collections
        let color = colorHex ?? CollectionColors.all[existing.count % CollectionColors.all.count]
        let new = BlockCollection(name: trimmed, colorHex: color, sortIndex: (existing.last?.sortIndex ?? 0) + 1)
        let pinned = existing.filter(\.isPinned).count
        if Pins.canPin(currentlyPinned: pinned) {
            new.isPinned = true
            new.pinIndex = pinned
        }
        context.insert(new)
        save()
        return new
    }

    var pinnedCollections: [BlockCollection] {
        collections.filter(\.isPinned).sorted { $0.pinIndex < $1.pinIndex }
    }

    func togglePin(_ target: BlockCollection) {
        if target.isPinned {
            target.isPinned = false
        } else {
            let pinned = pinnedCollections
            guard Pins.canPin(currentlyPinned: pinned.count) else {
                flash("The top bar holds \(Pins.limit) pins. Unpin one first.")
                return
            }
            target.isPinned = true
            target.pinIndex = (pinned.map(\.pinIndex).max() ?? -1) + 1
        }
        save()
    }

    /// Deletes the collection only. Its blocks go back to the Inbox, and the collections
    /// inside it move up to its parent. Ask first with `collectionToDelete`.
    func deleteCollection(_ target: BlockCollection) {
        for block in target.blocks ?? [] {
            block.collection = nil
            block.status = .inbox
        }
        for child in target.children ?? [] {
            child.parent = nil
            if let place = CollectionTree.move(child.uid, to: target.parent.map { .inside($0.uid) } ?? .topLevel, in: treeNodes) {
                child.parent = collection(place.parent)
                child.sortIndex = place.sortIndex
            }
        }
        if scope == .collection(target.uid) { scope = .all }
        if collectionToDelete == target.uid { collectionToDelete = nil }
        flash("Deleted \(target.name)")
        context.delete(target)
        save()
    }

    /// The text of the delete confirmation, with the count of blocks that go back to the Inbox.
    func deleteMessage(for target: BlockCollection) -> String {
        CollectionTree.deleteMessage(blockCount: target.blocks?.count ?? 0, childCount: target.children?.count ?? 0)
    }

    func rename(_ target: BlockCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingCollection = nil
        guard !trimmed.isEmpty, trimmed != target.name else { return }
        target.name = trimmed
        save()
    }

    /// The collection the window shows, if it shows one.
    var openCollection: BlockCollection? {
        if case .collection(let uid) = scope { collection(uid) } else { nil }
    }

    /// Collections in display order: each parent followed by its children.
    var collectionTree: [(collection: BlockCollection, depth: Int)] {
        let all = collections
        let byID = Dictionary(all.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        return CollectionTree.flatten(all.map(\.node)).compactMap { row in byID[row.id].map { ($0, row.depth) } }
    }

    private var treeNodes: [TreeNode] { collections.map(\.node) }

    /// Drag and drop, Move Into, and the top level. Returns false when the move isn't allowed
    /// (a collection can't go inside itself or its own child).
    @discardableResult
    func place(_ target: BlockCollection, _ placement: TreePlacement) -> Bool {
        guard let place = CollectionTree.move(target.uid, to: placement, in: treeNodes) else { return false }
        apply(place, to: target)
        return true
    }

    /// Move Up and Move Down among the collections that share its parent.
    @discardableResult
    func step(_ target: BlockCollection, up: Bool) -> Bool {
        guard let place = CollectionTree.step(target.uid, up: up, in: treeNodes) else { return false }
        apply(place, to: target)
        return true
    }

    /// The collections `target` can be moved into.
    func possibleParents(for target: BlockCollection) -> [BlockCollection] {
        let nodes = treeNodes
        return collectionTree.map(\.collection).filter {
            $0.uid != target.parent?.uid && CollectionTree.canNest(target.uid, under: $0.uid, in: nodes)
        }
    }

    private func apply(_ place: (parent: UUID?, sortIndex: Double), to target: BlockCollection) {
        target.parent = collection(place.parent)
        target.sortIndex = place.sortIndex
        save()
    }

    // MARK: Sort Inbox

    /// Inbox blocks, newest first, the order the Inbox shows them.
    var inboxUIDs: [UUID] {
        let inbox = BlockStatus.inbox.rawValue
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.statusRaw == inbox },
                                                sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.uid)
    }

    /// Opens Sort Inbox with a fresh run over everything in the Inbox.
    func startSorting() {
        sortSession = SortSession(inbox: inboxUIDs)
        selection = nil
        showsCollections = false
        viewMode = .sortInbox
    }

    /// Switches the window to a view mode. Sort Inbox starts a new run each time it opens.
    func show(_ mode: ViewMode) {
        guard mode.isAvailable else { return }
        if mode == .sortInbox, viewMode != .sortInbox { startSorting() } else { viewMode = mode }
    }

    var sortingBlock: Block? { block(sortSession.current) }

    /// True when M, D, → and ⌫ should sort: Sort Inbox shows a block, and no field or panel is open.
    var canSortNow: Bool {
        viewMode == .sortInbox && sortSession.current != nil && !showsCollections && !showsNewMenu && renamingCollection == nil
    }

    /// Keeps the run in step when the Inbox changes outside it (a save, an Undo).
    func syncSorting() {
        sortSession.sync(inbox: inboxUIDs)
    }

    /// The collection Sort Inbox suggests for a block: from its site and kind, else the
    /// collection the same site's blocks went to last.
    func suggestion(for target: Block) -> BlockCollection? {
        let all = collections
        let site = target.siteName
        let lastUsed = site.isEmpty ? nil : ((try? context.fetch(FetchDescriptor<Block>(
            predicate: #Predicate { $0.siteName == site && $0.collection != nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []).first?.collection?.uid
        let id = SortSuggestion.collection(site: site, kind: target.kindRaw, title: target.title,
                                           collections: all.map { ($0.uid, $0.name) }, lastUsedForSite: lastUsed)
        return all.first { $0.uid == id }
    }

    /// M, or a collection chip: the current block goes into a collection.
    func sortMove(to target: BlockCollection?, undo: UndoManager?) {
        guard let current = sortingBlock, let target else { return }
        sortSession.finish(.kept)
        today.sorted += 1
        move(current, to: target, undo: undo)
    }

    /// D: the current block is done with. It leaves the Inbox and stays in All.
    func sortDone() {
        guard let current = sortingBlock else { return }
        sortSession.finish(.done)
        today.sorted += 1
        current.status = .done
        noteInboxZero()
        save()
        flash("Marked done")
    }

    /// →: the current block goes to the back of the queue.
    func sortSkip() {
        sortSession.skip()
    }

    /// ⌫: the current block is deleted (Undo brings it back into the queue).
    func sortDelete(undo: UndoManager?) {
        guard let current = sortingBlock else { return }
        sortSession.finish(.deleted)
        today.sorted += 1
        delete([current.uid], undo: undo)
        flash("Deleted")
    }

    // MARK: Streak (S-061)

    /// Today's activity record, made on first use.
    var today: DayActivity {
        let number = DayActivity.number(for: .now)
        if let found = try? context.fetch(FetchDescriptor<DayActivity>(predicate: #Predicate { $0.day == number })).first {
            return found
        }
        let new = DayActivity(day: number)
        context.insert(new)
        return new
    }

    /// Marks today as an Inbox zero day once the Inbox is empty. Called after every action
    /// that can take a block out of the Inbox.
    func noteInboxZero() {
        guard inboxUIDs.isEmpty else { return }
        let record = today
        guard !record.reachedInboxZero else { return }
        record.reachedInboxZero = true
        streakDays = computeStreak()
    }

    /// Days in a row with Inbox zero. Stored, so the top bar redraws when it changes.
    private(set) var streakDays = 0

    func refreshStreak() {
        streakDays = computeStreak()
    }

    private func computeStreak() -> Int {
        let records = ((try? context.fetch(FetchDescriptor<DayActivity>())) ?? [])
            .map { DayRecord(day: $0.day, saved: $0.saved, reachedInboxZero: $0.reachedInboxZero) }
        return Streak.days(records, today: DayActivity.number(for: .now))
    }

    // MARK: Helpers

    func save() {
        do { try context.save() } catch { flash("Couldn’t save: \(error.localizedDescription)") }
    }

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { toast = nil }
        }
    }
}

/// Everything needed to bring a deleted block back with Undo.
private struct BlockCopy {
    let uid: UUID, kindRaw: String, urlString: String?, normalizedURL: String?, title: String, siteName: String
    let note: String, bodyText: String, checklistData: Data?, thumbnail: Data?, thumbnailAspect: Double
    let colorHex: Int?, statusRaw: String, enrichRaw: String, createdAt: Date, openedAt: Date?, collectionUID: UUID?

    init(_ b: Block) {
        uid = b.uid; kindRaw = b.kindRaw; urlString = b.urlString; normalizedURL = b.normalizedURL; title = b.title
        siteName = b.siteName; note = b.note; bodyText = b.bodyText; checklistData = b.checklistData
        thumbnail = b.thumbnail; thumbnailAspect = b.thumbnailAspect; colorHex = b.colorHex; statusRaw = b.statusRaw
        enrichRaw = b.enrichRaw; createdAt = b.createdAt; openedAt = b.openedAt; collectionUID = b.collection?.uid
    }

    func makeBlock(in model: AppModel) -> Block {
        let b = Block(kind: BlockKind(rawValue: kindRaw) ?? .link, title: title)
        b.uid = uid; b.urlString = urlString; b.normalizedURL = normalizedURL; b.siteName = siteName; b.note = note
        b.bodyText = bodyText; b.checklistData = checklistData; b.thumbnail = thumbnail; b.thumbnailAspect = thumbnailAspect
        b.colorHex = colorHex; b.statusRaw = statusRaw; b.enrichRaw = enrichRaw; b.createdAt = createdAt; b.openedAt = openedAt
        b.collection = model.collection(collectionUID)
        return b
    }
}

/// Mirrors the selection for menu commands, which don't observe @Observable models
/// (bama swift-swiftui skill, "Menu commands").
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published private(set) var selection: UUID?
    func update(_ uid: UUID?) { if selection != uid { selection = uid } }
}

extension BlockCollection {
    var node: TreeNode { TreeNode(id: uid, parent: parent?.uid, sortIndex: sortIndex) }
}
