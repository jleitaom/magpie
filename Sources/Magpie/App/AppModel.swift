import AppKit
import Carbon.HIToolbox
import MagpieKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What the Gallery shows.
enum Scope: Hashable {
    case all, inbox
    case collection(UUID)
    /// Every block with this tag (S-014).
    case tag(UUID)
    /// Archived blocks (S-022), and the ones that expired (S-021).
    case archive, expired
}

/// The view switcher's modes. Gallery and Sort Inbox exist so far (notes/PLAN.md).
enum ViewMode: String, CaseIterable, Identifiable {
    case gallery, journal, sortInbox, luckyDip, rediscover
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .journal: "Journal"
        case .sortInbox: "Sort Inbox"
        case .luckyDip: "Lucky Dip"
        case .rediscover: "Rediscover"
        }
    }

    var icon: KitIcon {
        switch self {
        case .gallery: .gallery
        case .journal: .journal
        case .sortInbox: .sortInbox
        case .luckyDip: .luckyDip
        case .rediscover: .rediscover
        }
    }

    var isAvailable: Bool { true }

    /// The view switcher's four; Rediscover opens from the View menu and Inbox zero.
    static var switcher: [ViewMode] { [.gallery, .journal, .sortInbox, .luckyDip] }

    /// ⌃⌘1 to ⌃⌘4, in the View menu.
    var shortcut: Character {
        switch self {
        case .gallery: "1"
        case .journal: "2"
        case .sortInbox: "3"
        case .luckyDip: "4"
        case .rediscover: "5"
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
    /// The running app's model, for the app delegate (Dock drops).
    @ObservationIgnored static weak var current: AppModel?

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    var scope: Scope = .all {
        didSet {
            guard scope != oldValue else { return }
            fitsTwentyMinutes = false
            // Each place opens in the view it was last seen in (Gallery or Journal).
            if viewMode == .gallery || viewMode == .journal { viewMode = rememberedView(for: scope) }
        }
    }
    var viewMode: ViewMode = .gallery
    var selection: UUID? { didSet { MenuState.shared.update(selection) } }
    var showsCollections = false
    var showsNewMenu = false
    var showsSortMenu = false
    /// Snapshot mode only: show the first-launch screen without emptying the sample library.
    var snapshotEmptyLibrary = false
    /// Search (S-031): open while the field shows; the words typed.
    var isSearching = false
    var searchQuery = ""
    /// "I have 20 minutes" in a collection's strip (S-073): only blocks that fit.
    var fitsTwentyMinutes = false
    /// Asks the details panel to put the cursor in its tag field (T, ⌘T).
    var focusTagField = false
    /// The tag waiting for the rename or delete prompt (S-015).
    var tagToRename: UUID?
    var tagToDelete: UUID?
    /// The Choose Picture sheet (#2): which block, and the page's pictures once they've loaded.
    var pictureChoice: PictureChoice?
    /// Lucky Dip (S-069–S-072, #3): the collection it picks from (nil: everything), the time
    /// limit, and whether the shuffle is running.
    var dipCollection: UUID?
    var dipMaxMinutes: Int?
    var isShuffling = false
    /// Titles flicking past during the shuffle.
    var shuffleTitle = ""
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
        refreshDipStats()
        expireDue()
        refreshDockBadge()
        registerQuickSave()
        registerScreenshot()
        // Things dropped on the Dock icon before the library was ready.
        if !AppDelegate.pendingURLs.isEmpty {
            let saved = receive(AppDelegate.pendingURLs, quietly: true)
            AppDelegate.pendingURLs = []
            if !saved.isEmpty {
                DropHUD.show(saved.count == 1 ? "Saved to Inbox" : "Saved \(saved.count) to Inbox")
                AppDelegate.stepBack()
            }
        }
        AppModel.current = self
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
        case .tag(let uid): all.filter { block in block.status != .archived && (block.tags ?? []).contains { $0.uid == uid } }
        case .archive: all.filter { $0.status == .archived }
        case .expired: all.filter { $0.status == .archived && $0.expiredAt != nil }
        }
    }

    // MARK: Saving

    /// Where new blocks go: into the open collection, or the Inbox.
    func place(_ block: Block) {
        if case .collection(let uid) = scope, let target = collection(uid) {
            block.collection = target
            block.status = .kept
            block.expiresAt = Expiry.date(addedAt: .now, days: target.defaultExpiryDays)
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
            flash("Already saved — moved to the top and refreshed")
            // Saving it again refreshes its title, picture, length and price.
            enrich(existing)
            return existing
        }
        let kind: BlockKind = switch Links.kind(url) {
        case .video: .video
        case .place: .place
        case .image: .image
        case .link: .link
        }
        // A place is named from its link ("Torre de Belém"); anything else starts with its site.
        let block = Block(kind: kind, title: Links.placeName(url) ?? Links.siteName(url))
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

    @discardableResult
    func saveImage(_ data: Data, name: String?, isScreenshot: Bool = false) -> Block {
        let block = Block(kind: .image, title: name ?? "Image")
        block.siteName = isScreenshot ? "Screenshot" : "Image"
        block.enrich = .pending
        place(block)
        let uid = block.uid
        Task {
            async let text = Ingest.recognizeText(data)
            let processed = await Ingest.process(data)
            let ocr = await text
            guard let block = self.block(uid) else { return }
            self.apply(processed, to: block)
            block.ocrText = ocr
            // A screenshot's text is its body text too (S-075).
            if isScreenshot, let ocr { block.bodyText = ocr }
            block.enrich = processed == nil ? .failed : .done
            self.save()
        }
        return block
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
        let uid = block.uid
        Task { await enrichNow(uid) }
    }

    /// Fetches a block's preview and page facts. Awaitable, so imports can go a few at a time.
    func enrichNow(_ uid: UUID) async {
        guard let block = block(uid), let url = block.url, !url.isFileURL, !enriching.contains(uid) else { return }
        let isPlace = block.kind == .place
        enriching.insert(uid)
        do {
            defer { enriching.remove(uid) }
            // The preview (title, picture) and the page's facts (length, price) load side by side.
            async let factsTask = isPlace ? nil : Ingest.fetchFacts(url)
            var preview = await Ingest.fetchPreview(url)
            let facts = await factsTask
            // The page sent us elsewhere with a meta refresh: preview that page instead.
            if let target = facts?.redirectedTo, preview?.title == nil || preview?.imageData == nil {
                preview = await Ingest.fetchPreview(target) ?? preview
            }
            var processed: ProcessedImage?
            if !isPlace, let data = preview?.imageData { processed = await Ingest.process(data) }
            guard let block = self.block(uid) else { return }   // deleted meanwhile
            apply(facts, to: block)
            // Title: oEmbed's (YouTube, Vimeo) beats the preview's. Either replaces only a stand-in
            // title (the site, or the channel name an earlier preview put there), never one you typed.
            let standIn = block.title == block.siteName || block.title == facts?.author
                || (isPlace && (block.title == "Google Maps" || block.title.hasPrefix("Search for")))
            if standIn, let title = (facts?.title ?? preview?.title).map(Titles.clean), !title.isEmpty {
                block.title = isPlace ? (Links.placeName(url) ?? title) : title
            }
            if isPlace {
                // Places show the mini map, not the map site's generic picture.
                block.thumbnail = nil
                block.colorHex = nil
            }
            if !block.pictureChosen { apply(processed, to: block) }   // a picture you chose stays
            block.enrich = preview == nil ? .failed : .done
            save()
        }
    }

    /// Video length, price, recipe and read time from the page (S-063).
    func apply(_ facts: PageFacts?, to block: Block) {
        guard let facts else { return }
        block.minutes = facts.minutes ?? block.minutes
        switch facts.kind {
        case .video where block.kind == .link:
            block.kind = .video
        case .product where block.kind == .link:
            block.kind = .product
            block.price = facts.price
            block.currency = facts.currency
        case .recipe:
            block.isRecipe = true
        default:
            break
        }
    }

    private func apply(_ processed: ProcessedImage?, to block: Block) {
        guard let processed else { return }
        block.thumbnail = processed.jpeg
        block.thumbnailAspect = processed.aspect
        block.colorHex = processed.color.map(Int.init)
    }

    // MARK: Choosing a picture (#2)

    /// Choose Picture…: opens the chooser and loads the pictures the block's page offers.
    func choosePicture(_ block: Block) {
        guard canChoosePicture(block), let url = block.url else { return }
        let uid = block.uid
        pictureChoice = PictureChoice(uid: uid)
        guard !SelfTest.requested else { return }   // the self-test never fetches pages
        Task {
            let choices = await Ingest.fetchPictureChoices(url)
            guard pictureChoice?.uid == uid else { return }   // closed or moved on meanwhile
            pictureChoice?.choices = choices
        }
    }

    /// Web links, videos and products: places show their map, and files and notes have no page.
    func canChoosePicture(_ block: Block) -> Bool {
        guard let scheme = block.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return block.kind != .place
    }

    /// Uses a chosen picture: it becomes the card's picture and color, and a refresh keeps it.
    func setPicture(_ image: ProcessedImage, for block: Block) {
        apply(image, to: block)
        block.pictureChosen = true
        save()
        pictureChoice = nil
        flash("Picture changed")
    }

    // MARK: Copying

    /// Copies a block's link (as a link and as text), or a note's text, so it pastes anywhere.
    func copy(_ block: Block, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if let url = block.url {
            pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
            flash("Link copied")
        } else {
            let text = block.kind == .checklist
                ? block.checklist.map { ($0.done ? "☑ " : "☐ ") + $0.text }.joined(separator: "\n")
                : block.bodyText
            pasteboard.setString([block.title, text].filter { !$0.isEmpty }.joined(separator: "\n\n"), forType: .string)
            flash("Copied")
        }
    }

    // MARK: Changing blocks

    func open(_ block: Block) {
        if let url = block.url {
            block.openedAt = .now
            save()
            openInBrowser(url)
        } else {
            selection = block.uid
        }
    }

    func move(_ block: Block, to target: BlockCollection?, undo: UndoManager?, announce: Bool = true) {
        let before = block.collection
        let beforeStatus = block.status
        block.collection = target
        block.status = target == nil ? .inbox : .kept
        // Moving in starts the collection's expiry; moving out (or out of the archive) ends it.
        block.expiresAt = Expiry.date(addedAt: .now, days: target?.defaultExpiryDays)
        block.expiredAt = nil
        block.statusBeforeArchiveRaw = nil
        noteInboxZero()
        save()
        let uid = block.uid
        undo?.registerUndo(withTarget: self) { model in
            guard let block = model.block(uid) else { return }
            model.move(block, to: before, undo: undo)
            block.status = beforeStatus
        }
        undo?.setActionName("Move")
        if announce { flash(target.map { "Moved to \($0.name)" } ?? "Moved to Inbox") }
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
    func createCollection(named name: String, colorHex: Int? = nil, pin: Bool = true, useDefaults: Bool = true) -> BlockCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = collections
        let color = colorHex ?? CollectionColors.all[existing.count % CollectionColors.all.count]
        let new = BlockCollection(name: trimmed, colorHex: color, sortIndex: (existing.last?.sortIndex ?? 0) + 1)
        if useDefaults { new.defaultExpiryDays = defaultExpiryDays }
        let pinned = existing.filter(\.isPinned).count
        if pin, Pins.canPin(currentlyPinned: pinned) {
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
        if dipCollection == target.uid { dipCollection = nil }   // Lucky Dip falls back to Everything
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
        isRenamingSortBlock = false
        sortSession = SortSession(inbox: inboxUIDs)
        selection = nil
        showsCollections = false
        viewMode = .sortInbox
    }

    /// Switches the window to a view mode. Sort Inbox starts a new run each time it opens.
    func show(_ mode: ViewMode) {
        guard mode.isAvailable else { return }
        if mode == .sortInbox, viewMode != .sortInbox { startSorting() }
        else if mode == .rediscover, viewMode != .rediscover { startRediscover() }
        else { viewMode = mode }
        if mode == .gallery || mode == .journal { remember(view: mode, for: scope) }
    }

    var sortingBlock: Block? { block(sortSession.current) }

    /// True when M, D, → and ⌫ should sort: Sort Inbox shows a block, and no field or panel is open.
    var canSortNow: Bool {
        viewMode == .sortInbox && sortSession.current != nil && !showsCollections && !showsNewMenu && renamingCollection == nil
            && !isRenamingSortBlock
    }

    /// Sort Inbox's card title is being edited (click it, or R); the sorting keys wait meanwhile.
    var isRenamingSortBlock = false

    /// Renames a block. An empty name is ignored.
    func rename(_ block: Block, to title: String) {
        let cleaned = Titles.clean(title)
        guard !cleaned.isEmpty, cleaned != block.title else { return }
        block.title = cleaned
        save()
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

    /// Today's activity record if there is one, without making it (safe while a view draws).
    var todayIfAny: DayActivity? {
        let number = DayActivity.number(for: .now)
        return try? context.fetch(FetchDescriptor<DayActivity>(predicate: #Predicate { $0.day == number })).first
    }

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

    // MARK: Lucky Dip (S-069–S-072)

    /// What Lucky Dip could pick from a collection and the collections inside it, or from
    /// everything (nil): blocks not done, archived or already in progress.
    func dipBlocks(from collection: UUID?) -> [Block] {
        let all = (try? context.fetch(FetchDescriptor<Block>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let open = all.filter { $0.status == .inbox || $0.status == .kept }
        guard let collection else { return open }
        let inside = subtree(of: collection)
        return open.filter { $0.collection.map { inside.contains($0.uid) } ?? false }
    }

    /// A collection and every collection nested inside it.
    func subtree(of root: UUID) -> Set<UUID> {
        let all = collections
        var found: Set<UUID> = [root]
        var grew = true
        while grew {
            grew = false
            for child in all where !found.contains(child.uid) {
                if let parent = child.parent?.uid, found.contains(parent) { found.insert(child.uid); grew = true }
            }
        }
        return found
    }

    /// The name Lucky Dip shows for where it picks from: "Everything" or the collection's name.
    var dipSourceName: String {
        collection(dipCollection)?.name ?? "Everything"
    }

    /// The block you started and haven't finished, if any (newest first).
    var inProgressBlock: Block? {
        let started = BlockStatus.inProgress.rawValue
        return try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.statusRaw == started },
                                                          sortBy: [SortDescriptor(\.openedAt, order: .reverse)])).first
    }

    /// Today's pick, while it's still waiting.
    var dipPick: Block? {
        guard let block = block(todayIfAny?.pickUID), block.status == .inbox || block.status == .kept else { return nil }
        return block
    }

    var spinsToday: Int { todayIfAny?.spins ?? 0 }
    var respinsLeft: Int { LuckyDip.respinsLeft(spinsToday: spinsToday) }

    /// What the Lucky Dip menu needs, passed into the menu bar so it redraws.
    var dipMenuState: DipMenuState {
        guard viewMode == .luckyDip else { return DipMenuState() }
        return DipMenuState(canSpin: canSpin && inProgressBlock == nil, hasPick: dipPick != nil, inProgress: inProgressBlock != nil)
    }
    var canSpin: Bool { LuckyDip.canSpin(spinsToday: spinsToday) && !isShuffling }

    /// Randomize or Spin again: a short shuffle of titles, then one block lands as today's pick.
    /// The first spin of the day is free, then 2 re-spins.
    func spin(reduceMotion: Bool) {
        guard canSpin else { return }
        let pool = dipBlocks(from: dipCollection)
        let candidates = pool.map { DipCandidate(id: $0.uid, minutes: $0.minutes, timesSkipped: $0.timesSkipped) }
        guard let chosen = LuckyDip.pick(from: candidates, maxMinutes: dipMaxMinutes, avoiding: todayIfAny?.pickUID) else {
            flash(pool.isEmpty ? "Nothing to pick from in \(dipSourceName)" : "Nothing in \(dipSourceName) fits that time")
            return
        }
        let record = today
        record.spins += 1
        record.pickUID = nil
        save()
        let fitting = LuckyDip.fitting(candidates, maxMinutes: dipMaxMinutes).compactMap { c in pool.first { $0.uid == c.id }?.title }
        isShuffling = true
        Task {
            // About a second of titles flicking past; none with Reduce Motion.
            if !reduceMotion {
                for step in 0..<12 {
                    shuffleTitle = fitting.randomElement() ?? ""
                    try? await Task.sleep(for: .milliseconds(50 + step * 8))
                }
            }
            record.pickUID = chosen
            isShuffling = false
            save()
        }
    }

    /// Start reading (watching, …): the pick opens and is marked In progress.
    func startPick(_ block: Block) {
        block.status = .inProgress
        if let url = block.url {
            block.openedAt = .now
            openInBrowser(url)
        } else {
            block.openedAt = .now
            selection = block.uid
        }
        if today.pickUID == block.uid { today.pickUID = nil }
        save()
    }

    /// Mark as finished: Lucky Dip won't pick it again, and it counts toward the dip streak and this week.
    func finishPick(_ block: Block) {
        block.status = .done
        block.finishedAt = .now
        today.finished += 1
        if today.pickUID == block.uid { today.pickUID = nil }
        save()
        refreshDipStats()
        flash("Finished. One less to get to")
    }

    /// Not today: the pick goes back, and comes up less often from now on.
    func notToday(_ block: Block) {
        block.timesSkipped += 1
        today.pickUID = nil
        save()
    }

    /// "Still want this?" answered yes: Lucky Dip treats it as new again.
    func keepWanting(_ block: Block) {
        block.timesSkipped = 0
        save()
    }

    /// The dip streak and the picks finished this week (Monday to Sunday). Stored so the stats redraw.
    private(set) var dipStreak = 0
    private(set) var finishedThisWeek = 0

    func refreshDipStats() {
        let records = (try? context.fetch(FetchDescriptor<DayActivity>())) ?? []
        let todayNumber = DayActivity.number(for: .now)
        let finishedDays = Set(records.filter { $0.finished > 0 }.map(\.day))
        dipStreak = LuckyDip.streak(finishedOn: finishedDays, today: todayNumber)
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: .now)
        // Calendar weekday: 1 = Sunday … 7 = Saturday. ISO: 1 = Monday … 7 = Sunday.
        let iso = weekday == 1 ? 7 : weekday - 1
        let start = LuckyDip.weekStart(today: todayNumber, weekday: iso)
        finishedThisWeek = records.filter { $0.day >= start && $0.day <= todayNumber }.map(\.finished).reduce(0, +)
    }

    // MARK: Tags (S-014, S-015)

    var tags: [Tag] {
        ((try? context.fetch(FetchDescriptor<Tag>())) ?? []).sorted { Tags.key($0.name) < Tags.key($1.name) }
    }

    func tag(_ uid: UUID?) -> Tag? {
        guard let uid else { return nil }
        return try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.uid == uid })).first
    }

    /// The tag with this name (any case), made if it doesn't exist yet.
    func tag(named name: String) -> Tag? {
        let cleaned = Tags.clean(name)
        guard !cleaned.isEmpty else { return nil }
        let all = tags
        if let found = all.first(where: { Tags.key($0.name) == Tags.key(cleaned) }) { return found }
        let new = Tag(name: cleaned, colorHex: CollectionColors.all[all.count % CollectionColors.all.count])
        context.insert(new)
        return new
    }

    /// Adds one or more tags ("jazz, vinyl") to a block. A tag it already has isn't added twice.
    func addTags(_ text: String, to block: Block) {
        for name in Tags.parse(text) {
            guard let tag = tag(named: name), !(block.tags ?? []).contains(where: { $0.uid == tag.uid }) else { continue }
            block.tags = (block.tags ?? []) + [tag]
        }
        save()
    }

    func removeTag(_ tag: Tag, from block: Block) {
        block.tags = (block.tags ?? []).filter { $0.uid != tag.uid }
        save()
    }

    /// Renames a tag. Renaming to another tag's name (any case) merges the two into that one.
    @discardableResult
    func renameTag(_ tag: Tag, to name: String) -> Bool {
        let cleaned = Tags.clean(name)
        tagToRename = nil
        guard !cleaned.isEmpty else { return false }
        if let other = tags.first(where: { $0.uid != tag.uid && Tags.key($0.name) == Tags.key(cleaned) }) {
            for block in tag.blocks ?? [] where !(block.tags ?? []).contains(where: { $0.uid == other.uid }) {
                block.tags = (block.tags ?? []) + [other]
            }
            if scope == .tag(tag.uid) { scope = .tag(other.uid) }
            context.delete(tag)
            save()
            flash("Merged into \(other.name)")
            return true
        }
        tag.name = cleaned
        save()
        return false
    }

    func recolor(_ tag: Tag, to hex: Int) {
        tag.colorHex = hex
        save()
    }

    /// Deletes the tag only: it comes off its blocks, and the blocks stay.
    func deleteTag(_ tag: Tag) {
        if scope == .tag(tag.uid) { scope = .all }
        tagToDelete = nil
        flash("Deleted tag \(tag.name)")
        context.delete(tag)
        save()
    }

    var openTag: Tag? {
        if case .tag(let uid) = scope { tag(uid) } else { nil }
    }

    // MARK: Order and view per place (S-065, S-067)

    /// Order and view for All, the Inbox and tags, kept in preferences ("all", "inbox", "tag-…").
    /// Collections keep theirs in the database, so they sync with the collection.
    struct PlacePrefs: Codable, Equatable {
        var order: String?
        var view: String?
        var seed: UInt64 = 0
    }

    private(set) var placePrefs: [String: PlacePrefs] = {
        guard let data = UserDefaults.standard.data(forKey: AppModel.placePrefsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PlacePrefs].self, from: data)) ?? [:]
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(placePrefs), forKey: Self.placePrefsKey) }
    }

    /// A demo, test or snapshot library (APP_STORE in /tmp) keeps its own choices, so it never
    /// changes how your real library is sorted.
    nonisolated static var placePrefsKey: String {
        let store = ProcessInfo.processInfo.environment["APP_STORE"] ?? ""
        return store.isEmpty ? "placePrefs" : "placePrefs-" + (store as NSString).lastPathComponent
    }

    private func key(_ scope: Scope) -> String? {
        switch scope {
        case .all: "all"
        case .inbox: "inbox"
        case .tag(let uid): "tag-\(uid.uuidString)"
        case .archive: "archive"
        case .expired: "expired"
        case .collection: nil
        }
    }

    func order(for scope: Scope) -> BlockOrder {
        if case .collection(let uid) = scope { return collection(uid)?.sortOrderRaw.flatMap(BlockOrder.init) ?? .newest }
        return key(scope).flatMap { placePrefs[$0]?.order }.flatMap(BlockOrder.init) ?? .newest
    }

    /// Chooses how a place is sorted. Choosing Shuffle again deals a new order.
    func setOrder(_ order: BlockOrder, for scope: Scope) {
        let seed = UInt64.random(in: 1...UInt64.max)
        if case .collection(let uid) = scope, let target = collection(uid) {
            target.sortOrderRaw = order.rawValue
            if order == .shuffle { target.shuffleSeed = Int(truncatingIfNeeded: seed) }
            save()
        } else if let key = key(scope) {
            var prefs = placePrefs[key] ?? PlacePrefs()
            prefs.order = order.rawValue
            if order == .shuffle { prefs.seed = seed }
            placePrefs[key] = prefs
        }
    }

    private func seed(for scope: Scope) -> UInt64 {
        if case .collection(let uid) = scope { return UInt64(bitPattern: Int64(collection(uid)?.shuffleSeed ?? 0)) }
        return key(scope).flatMap { placePrefs[$0]?.seed } ?? 0
    }

    func rememberedView(for scope: Scope) -> ViewMode {
        let raw = if case .collection(let uid) = scope { collection(uid)?.viewModeRaw } else { key(scope).flatMap { placePrefs[$0]?.view } }
        return raw.flatMap(ViewMode.init) ?? .gallery
    }

    private func remember(view: ViewMode, for scope: Scope) {
        if case .collection(let uid) = scope, let target = collection(uid) {
            guard target.viewModeRaw != view.rawValue else { return }
            target.viewModeRaw = view.rawValue
            save()
        } else if let key = key(scope) {
            var prefs = placePrefs[key] ?? PlacePrefs()
            prefs.view = view.rawValue
            placePrefs[key] = prefs
        }
    }

    /// Blocks in the place's chosen order.
    func ordered(_ blocks: [Block], in scope: Scope) -> [Block] {
        let items = blocks.map { OrderItem(id: $0.uid, createdAt: $0.createdAt, minutes: $0.minutes, title: $0.title,
                                           site: $0.siteName, color: $0.tint, sortIndex: $0.sortIndex) }
        let byID = Dictionary(blocks.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        return order(for: scope).sorted(items, seed: seed(for: scope)).compactMap { byID[$0] }
    }

    /// The place's name, for the Journal's heading and the Sort menu.
    func placeName(_ scope: Scope) -> String {
        switch scope {
        case .all: "Everything"
        case .inbox: "Inbox"
        case .collection(let uid): collection(uid)?.name ?? "Collection"
        case .tag(let uid): tag(uid).map { "#\($0.name)" } ?? "Tag"
        case .archive: "Archive"
        case .expired: "Expired"
        }
    }

    // MARK: Archive (S-022) and expiry (S-021)

    /// Hides a block from collections, All and tags. It stays in the Archive (and, later, search).
    func archive(_ block: Block, undo: UndoManager? = nil) {
        guard block.status != .archived else { return }
        let before = block.status
        block.statusBeforeArchiveRaw = before.rawValue
        block.status = .archived
        if selection == block.uid, scope != .archive { selection = nil }
        noteInboxZero()
        save()
        let uid = block.uid
        undo?.registerUndo(withTarget: self) { model in if let block = model.block(uid) { model.unarchive(block) } }
        undo?.setActionName("Archive")
        flash("Archived")
    }

    /// Puts an archived (or expired) block back where it was.
    func unarchive(_ block: Block) {
        guard block.status == .archived else { return }
        block.status = block.statusBeforeArchiveRaw.flatMap(BlockStatus.init) ?? (block.collection == nil ? .inbox : .kept)
        block.statusBeforeArchiveRaw = nil
        block.expiredAt = nil
        block.expiresAt = nil
        save()
        flash("Back in \(block.collection?.name ?? "the Inbox")")
    }

    /// Keep: an expiring block stops expiring, and Rediscover won't show it again for a while.
    func keep(_ block: Block) {
        block.expiresAt = nil
        block.lastShownAt = .now
        save()
    }

    /// Blocks added to this collection from now on expire after `days`. Existing ones don't change.
    func setExpiry(_ target: BlockCollection, days: Int?) {
        target.defaultExpiryDays = days
        save()
        flash(days.map { "New blocks in \(target.name) expire after \($0) days" } ?? "Blocks in \(target.name) don't expire")
    }

    /// Archives every block whose expiry passed. Runs at launch and when the window changes place.
    func expireDue(now: Date = .now) {
        let archived = BlockStatus.archived.rawValue
        let due = ((try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.expiresAt != nil && $0.statusRaw != archived }))) ?? [])
            .filter { Expiry.isDue($0.expiresAt, now: now) }
        guard !due.isEmpty else { return }
        for block in due {
            block.statusBeforeArchiveRaw = block.status.rawValue
            block.status = .archived
            block.expiredAt = now
        }
        save()
        flash(due.count == 1 ? "1 block expired" : "\(due.count) blocks expired")
    }

    var archiveCount: Int {
        let archived = BlockStatus.archived.rawValue
        return (try? context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.statusRaw == archived }))) ?? 0
    }

    var expiredCount: Int {
        let archived = BlockStatus.archived.rawValue
        return (try? context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.statusRaw == archived && $0.expiredAt != nil }))) ?? 0
    }

    // MARK: Rediscover (S-020)

    /// Today's five, picked the first time Rediscover opens today.
    var rediscoverIDs: [UUID] {
        (todayIfAny?.rediscoverRaw ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    /// The card showing now, or nil when today's five are done (or there were none).
    var rediscoverBlock: Block? {
        let ids = rediscoverIDs
        let done = todayIfAny?.rediscoverDone ?? 0
        return ids.indices.contains(done) ? block(ids[done]) : nil
    }

    /// Opens Rediscover, picking today's five the first time today.
    func startRediscover() {
        expireDue()
        let record = today
        if record.rediscoverRaw == nil {
            let all = (try? context.fetch(FetchDescriptor<Block>())) ?? []
            let candidates = all.filter { $0.status == .kept || $0.status == .inbox }
                .map { RediscoverCandidate(id: $0.uid, createdAt: $0.createdAt, openedAt: $0.openedAt,
                                           lastShownAt: $0.lastShownAt, timesSkipped: $0.timesSkipped) }
            record.rediscoverRaw = Rediscover.pick(from: candidates, now: .now).map(\.uuidString).joined(separator: ",")
            record.rediscoverDone = 0
            save()
        }
        selection = nil
        showsCollections = false
        viewMode = .rediscover
    }

    /// The card's actions. Each one moves on to the next of today's five.
    func rediscoverKeep() {
        guard let block = rediscoverBlock else { return }
        keep(block)
        nextRediscover()
    }

    func rediscoverSkip() {
        guard let block = rediscoverBlock else { return }
        block.timesSkipped += 1
        block.lastShownAt = .now
        nextRediscover()
    }

    func rediscoverArchive() {
        guard let block = rediscoverBlock else { return }
        block.lastShownAt = .now
        archive(block)
        nextRediscover()
    }

    private func nextRediscover() {
        today.rediscoverDone += 1
        save()
        refreshDockBadge()
    }

    /// True when K, A and → act on a Rediscover card (and no field or panel is open).
    var canRediscoverNow: Bool {
        viewMode == .rediscover && rediscoverBlock != nil && !showsCollections && !showsNewMenu && renamingCollection == nil
    }

    // MARK: Search (S-031)

    /// Opens the search field (⌘F). Search looks everywhere, the Archive included.
    func startSearch() {
        isSearching = true
        if viewMode != .gallery && viewMode != .journal { viewMode = rememberedView(for: scope) }
        selection = nil
    }

    func endSearch() {
        isSearching = false
        searchQuery = ""
    }

    var searchTerms: [String] { isSearching ? Search.terms(searchQuery) : [] }

    /// Blocks matching the search: title matches first, then newest.
    func searchResults(_ query: String, in all: [Block]) -> [Block] {
        let terms = Search.terms(query)
        guard !terms.isEmpty else { return [] }
        // Folded text is cached per block, so each keystroke only compares strings.
        var titleHits: [(block: Block, title: Bool, date: Date)] = []
        for block in all {
            let index = indexFor(block)
            guard Search.matches(index: index.all, terms: terms) else { continue }
            titleHits.append((block, Search.matches(index: index.title, terms: terms), block.createdAt))
        }
        return titleHits.sorted { $0.title == $1.title ? $0.date > $1.date : $0.title }.map(\.block)
    }

    /// Each block's folded search text, built once and dropped whenever anything is saved
    /// (an edit, a tag, a fetched preview), so typing in the search field stays fast.
    @ObservationIgnored private var searchCache: [UUID: (all: String, title: String)] = [:]

    private func indexFor(_ block: Block) -> (all: String, title: String) {
        if let cached = searchCache[block.uid] { return cached }
        let index = (all: block.searchIndex, title: Search.index([block.title]))
        searchCache[block.uid] = index
        return index
    }

    // MARK: Totals (S-073, S-074)

    /// "3 h 10 min of video saved", when a place holds videos with known lengths.
    func videoTotal(_ blocks: [Block]) -> String? {
        let minutes = blocks.filter { $0.kind == .video }.map(\.minutes)
        let total = LuckyDip.totalTime(minutes)
        return total.isEmpty ? nil : total
    }

    /// "€442 + $60", when a place holds products with prices.
    func priceTotal(_ blocks: [Block]) -> String? {
        let prices = blocks.compactMap { block in block.price.map { (amount: $0, currency: block.currency) } }
        return prices.isEmpty ? nil : Totals.money(prices, fallback: Locale.current.currency?.identifier ?? "EUR")
    }

    // MARK: Quick Save (S-030)

    @ObservationIgnored private(set) lazy var quickSavePanel = QuickSavePanel(model: self)
    @ObservationIgnored private var quickSaveHotKey: HotKey?

    /// The global shortcut, from Settings. Stored, so Settings redraws when it changes.
    var quickSaveShortcut: QuickSaveShortcut = QuickSaveShortcut(rawValue: UserDefaults.standard.string(forKey: "quickSaveShortcut") ?? "")
        ?? .controlOptionSpace {
        didSet {
            UserDefaults.standard.set(quickSaveShortcut.rawValue, forKey: "quickSaveShortcut")
            registerQuickSave()
        }
    }

    /// Whether the shortcut is registered (another app may hold it).
    private(set) var quickSaveShortcutWorks = true

    func registerQuickSave() {
        quickSaveHotKey = nil
        // Test runs never take the shortcut from the Magpie you use.
        guard !SelfTest.requested, ProcessInfo.processInfo.environment["APP_SNAPSHOT"] == nil else { return }
        guard let keys = quickSaveShortcut.carbon else { quickSaveShortcutWorks = true; return }
        quickSaveHotKey = HotKey(id: 1, keyCode: keys.keyCode, modifiers: keys.modifiers) { [weak self] in
            self?.quickSavePanel.open()
        }
        quickSaveShortcutWorks = quickSaveHotKey != nil
    }

    /// Saves what Quick Save shows, with the title, collection, tags and note from the panel.
    /// It goes to the chosen collection (the Inbox by default), whatever the window shows.
    @discardableResult
    func quickSave(_ edited: QuickSavePanel.Edited) -> Block? {
        let block: Block?
        switch edited.draft.content {
        case .web(let url):
            block = url.isFileURL ? saveFile(url) : save(url: url)
        case .text(let text):
            let note = Block(kind: .note, title: Titles.firstLine(text))
            note.bodyText = text
            note.siteName = "Note"
            place(note)
            block = note
        case .image(let data):
            block = saveImage(data, name: nil)
        case .nothing:
            block = nil
        }
        guard let block else { return nil }
        let title = Titles.clean(edited.title)
        if !title.isEmpty { block.title = title }
        if !edited.note.isEmpty { block.note = edited.note }
        move(block, to: collection(edited.collection), undo: nil)
        if !edited.tags.isEmpty { addTags(edited.tags, to: block) }
        save()
        flash("Saved to \(block.collection?.name ?? "the Inbox")")
        return block
    }

    private func saveFile(_ url: URL) -> Block? {
        save(.file(url))
        return (try? context.fetch(FetchDescriptor<Block>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?.first
    }

    // MARK: Manual order (S-066) and Quick Look (S-032)

    /// Drops `moving` onto `target` in the order shown. A place sorted any other way switches to
    /// Manual first, numbering what you see, so nothing jumps.
    func reorder(_ moving: UUID, onto target: UUID, shown: [Block], in scope: Scope) {
        if order(for: scope) != .manual {
            for (block, index) in zip(shown, ManualOrder.numbered(shown.count)) { block.sortIndex = index }
            setOrder(.manual, for: scope)
        }
        let indexes = Dictionary(shown.map { ($0.uid, $0.sortIndex) }, uniquingKeysWith: { first, _ in first })
        guard let index = ManualOrder.drop(moving, onto: target, in: shown.map(\.uid), indexes: indexes),
              let block = shown.first(where: { $0.uid == moving }) else { return }
        block.sortIndex = index
        save()
    }

    /// The file Quick Look shows: the block's file, or its picture written to a temporary file.
    var quickLookURL: URL?

    func quickLook(_ block: Block?) {
        guard let block else { return }
        if quickLookURL != nil { quickLookURL = nil; return }
        if let url = block.url, url.isFileURL {
            quickLookURL = url
        } else if let data = block.thumbnail {
            let file = FileManager.default.temporaryDirectory.appending(path: "Magpie-\(block.uid.uuidString).jpg")
            try? data.write(to: file)
            quickLookURL = file
        } else {
            flash("Nothing to preview")
        }
    }

    // MARK: Import bookmarks (S-042)

    /// The bookmarks file being previewed in the import sheet.
    var bookmarkImport: BookmarkImport?

    struct BookmarkImport: Identifiable {
        let id = UUID()
        let file: String
        let root: BookmarkFolder
        /// Folder ids ticked for import (all at first), and whether loose links go to the Inbox.
        var chosen: Set<String>
        var includeLoose = true
    }

    /// File → Import Bookmarks: pick the HTML file a browser exported, then preview it.
    func chooseBookmarksFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.prompt = "Preview"
        panel.message = "Choose the bookmarks file you exported from Safari (File ▸ Export ▸ Bookmarks), Chrome or Firefox."
        guard panel.runModal() == .OK, let url = panel.url, let html = try? String(contentsOf: url, encoding: .utf8) else { return }
        previewBookmarks(html, file: url.lastPathComponent)
    }

    func previewBookmarks(_ html: String, file: String) {
        let root = BookmarkFile.parse(html)
        guard root.total > 0 else { flash("No bookmarks found in \(file)"); return }
        bookmarkImport = BookmarkImport(file: file, root: root, chosen: Set(root.flattened().map(\.folder.id)))
    }

    var existingURLs: Set<String> {
        Set(((try? context.fetch(FetchDescriptor<Block>())) ?? []).compactMap(\.normalizedURL))
    }

    /// Imports the chosen folders: folders become nested collections (reusing ones with the same
    /// name in the same place), duplicates are skipped, and previews load a few at a time.
    @discardableResult
    func importBookmarks(_ plan: BookmarkImport) -> (saved: Int, duplicates: Int) {
        let result = BookmarkFile.plan(plan.root, folders: plan.chosen, includeLoose: plan.includeLoose, existing: existingURLs)
        var folders: [String: BlockCollection] = [:]
        func collection(for path: [String]) -> BlockCollection? {
            guard !path.isEmpty else { return nil }
            let key = path.joined(separator: "/")
            if let found = folders[key] { return found }
            let parent = collection(for: Array(path.dropLast()))
            let parentID = parent?.uid
            let name = path.last!
            let existing = collections.first { $0.parent?.uid == parentID && Tags.key($0.name) == Tags.key(name) }
            let made = existing ?? createCollection(named: name, pin: false, useDefaults: false)
            if existing == nil, let made, let parent { place(made, .inside(parent.uid)) }
            folders[key] = made
            return made
        }
        var queue: [UUID] = []
        for item in result.items {
            let block = Block(kind: { switch Links.kind(item.link.url) {
                case .video: .video
                case .place: .place
                case .image: .image
                case .link: .link
            } }(), title: item.link.title)
            block.urlString = item.link.url.absoluteString
            block.normalizedURL = Links.normalize(item.link.url)
            block.siteName = Links.siteName(item.link.url)
            block.createdAt = item.link.added ?? .now
            if let target = collection(for: item.folder) {
                block.collection = target
                block.status = .kept
            } else {
                block.status = .inbox
            }
            block.enrich = .pending
            context.insert(block)
            queue.append(block.uid)
        }
        save()
        bookmarkImport = nil
        flash("Imported \(result.items.count) bookmarks" + (result.duplicates > 0 ? ", skipped \(result.duplicates) already saved" : ""))
        // Previews in the background, three at a time, so a big import never floods the network.
        Task {
            for start in stride(from: 0, to: queue.count, by: Self.importBatch) {
                let batch = queue[start..<min(start + Self.importBatch, queue.count)]
                await withTaskGroup(of: Void.self) { group in
                    for uid in batch {
                        group.addTask {
                            await self.importStarted()
                            await self.enrichNow(uid)
                            await self.importFinished()
                        }
                    }
                }
            }
        }
        return (result.items.count, result.duplicates)
    }

    static let importBatch = 3
    /// Import previews loading now, and the most there ever were at once (the self-test checks it).
    @ObservationIgnored private(set) var importInFlight = 0
    @ObservationIgnored private(set) var importInFlightMost = 0

    private func importStarted() {
        importInFlight += 1
        importInFlightMost = max(importInFlightMost, importInFlight)
    }

    private func importFinished() { importInFlight -= 1 }

    // MARK: Dock drop (S-041) and screenshots (S-075)

    /// Links, images and files dropped on the Dock icon (or opened with Magpie) go to the Inbox.
    /// `quietly`: no message in the window (the Dock drop shows its own by the Dock).
    @discardableResult
    func receive(_ urls: [URL], quietly: Bool = false) -> [Block] {
        var saved: [Block] = []
        for url in urls {
            var block: Block?
            if url.isFileURL, ["webloc", "url"].contains(url.pathExtension.lowercased()), let link = Self.link(inShortcut: url) {
                block = save(url: link)
            } else if url.isFileURL {
                if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image), let data = try? Data(contentsOf: url) {
                    block = saveImage(data, name: url.deletingPathExtension().lastPathComponent)
                } else {
                    block = saveFile(url)
                }
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                block = save(url: url)
            }
            if let block {
                if block.collection != nil || block.status != .inbox { move(block, to: nil, undo: nil, announce: false) }
                saved.append(block)
            }
        }
        if !saved.isEmpty, !quietly { flash(saved.count == 1 ? "Saved to the Inbox" : "Saved \(saved.count) to the Inbox") }
        return saved
    }

    /// The address in a .webloc (Safari) or .url (Windows) link file.
    static func link(inShortcut file: URL) -> URL? {
        webLink(inShortcut: file).flatMap { Links.parse($0.absoluteString) }
    }

    private static func webLink(inShortcut file: URL) -> URL? {
        if file.pathExtension.lowercased() == "webloc",
           let data = try? Data(contentsOf: file),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let text = plist["URL"] as? String {
            return URL(string: text)
        }
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("URL=") }.flatMap { URL(string: String($0.dropFirst(4))) }
    }

    @ObservationIgnored private var screenshotHotKey: HotKey?

    /// ⌃⌥S saves a screenshot (Settings → General).
    var screenshotShortcutOn: Bool = UserDefaults.standard.object(forKey: "screenshotShortcutOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(screenshotShortcutOn, forKey: "screenshotShortcutOn")
            registerScreenshot()
        }
    }

    func registerScreenshot() {
        screenshotHotKey = nil
        guard screenshotShortcutOn, !SelfTest.requested, ProcessInfo.processInfo.environment["APP_SNAPSHOT"] == nil else { return }
        screenshotHotKey = HotKey(id: 2, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.takeScreenshot()
        }
    }

    /// Select part of the screen with macOS's own tool; the picture goes to the Inbox and its
    /// text is read so search finds it. The first time, it says why it needs Screen Recording.
    func takeScreenshot() {
        if !CGPreflightScreenCaptureAccess(), !UserDefaults.standard.bool(forKey: "explainedScreenRecording") {
            UserDefaults.standard.set(true, forKey: "explainedScreenRecording")
            let alert = NSAlert()
            alert.messageText = "Magpie needs to see your screen to save a screenshot"
            alert.informativeText = "macOS will ask for Screen Recording permission. Magpie only keeps the area you select, as a block in your Inbox, and reads its text so you can search it. Nothing leaves your Mac."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            CGRequestScreenCaptureAccess()
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "Magpie-screenshot-\(UUID().uuidString).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-i", "-x", file.path]   // -i: select an area or window; -x: no sound
        capture.terminationHandler = { _ in
            Task { @MainActor in
                guard let data = try? Data(contentsOf: file) else { return }   // Escape: nothing saved
                try? FileManager.default.removeItem(at: file)
                self.saveScreenshot(data)
            }
        }
        try? capture.run()
    }

    @discardableResult
    func saveScreenshot(_ data: Data) -> Block {
        let name = "Screenshot " + Date.now.formatted(.dateTime.day().month().hour().minute())
        let block = saveImage(data, name: name, isScreenshot: true)
        if block.collection != nil { move(block, to: nil, undo: nil, announce: false) }
        flash("Screenshot saved to the Inbox")
        return block
    }

    // MARK: Opening pages

    /// What the self-test would have opened. Test runs never open your browser.
    @ObservationIgnored private(set) var lastOpenedURL: URL?

    /// Opens a page in your default browser, except during the self-test.
    /// Opens web links in the browser and saved files in their app. Any other kind of address
    /// (one planted in an imported export, say) is refused, so opening a block never starts another app's action.
    func openInBrowser(_ url: URL) {
        guard Links.isOpenable(url) else {
            flash("Magpie only opens web links and files")
            return
        }
        lastOpenedURL = url
        guard !SelfTest.requested else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Settings (S-053)

    /// New collections expire their blocks after this many days. Nil: never.
    var defaultExpiryDays: Int? = (UserDefaults.standard.object(forKey: "defaultExpiryDays") as? Int) {
        didSet { UserDefaults.standard.set(defaultExpiryDays, forKey: "defaultExpiryDays") }
    }

    /// Rediscover's count for today on the Dock icon.
    var rediscoverDockBadge: Bool = UserDefaults.standard.bool(forKey: "rediscoverDockBadge") {
        didSet {
            UserDefaults.standard.set(rediscoverDockBadge, forKey: "rediscoverDockBadge")
            refreshDockBadge()
        }
    }

    /// Old saves still waiting in today's Rediscover: what's left of today's five, or, before
    /// Rediscover opened today, how many it would pick.
    var rediscoverWaiting: Int {
        if todayIfAny?.rediscoverRaw != nil {
            return max(rediscoverIDs.count - (todayIfAny?.rediscoverDone ?? 0), 0)
        }
        let all = (try? context.fetch(FetchDescriptor<Block>())) ?? []
        let eligible = all.filter { ($0.status == .kept || $0.status == .inbox) && Rediscover.isEligible(
            RediscoverCandidate(id: $0.uid, createdAt: $0.createdAt, openedAt: $0.openedAt, lastShownAt: $0.lastShownAt,
                                timesSkipped: $0.timesSkipped), now: .now) }
        return min(eligible.count, Rediscover.perDay)
    }

    func refreshDockBadge() {
        let count = rediscoverDockBadge ? rediscoverWaiting : 0
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // MARK: Helpers

    func save() {
        searchCache.removeAll()
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

/// The Choose Picture sheet's state: nil choices while the page loads.
struct PictureChoice: Identifiable {
    let uid: UUID
    var choices: [ProcessedImage]?
    var id: UUID { uid }
}

/// Everything needed to bring a deleted block back with Undo.
private struct BlockCopy {
    let uid: UUID, kindRaw: String, urlString: String?, normalizedURL: String?, title: String, siteName: String
    let note: String, bodyText: String, checklistData: Data?, thumbnail: Data?, thumbnailAspect: Double, pictureChosen: Bool
    let colorHex: Int?, statusRaw: String, enrichRaw: String, createdAt: Date, openedAt: Date?, collectionUID: UUID?

    init(_ b: Block) {
        uid = b.uid; kindRaw = b.kindRaw; urlString = b.urlString; normalizedURL = b.normalizedURL; title = b.title
        siteName = b.siteName; note = b.note; bodyText = b.bodyText; checklistData = b.checklistData
        thumbnail = b.thumbnail; thumbnailAspect = b.thumbnailAspect; pictureChosen = b.pictureChosen; colorHex = b.colorHex; statusRaw = b.statusRaw
        enrichRaw = b.enrichRaw; createdAt = b.createdAt; openedAt = b.openedAt; collectionUID = b.collection?.uid
    }

    func makeBlock(in model: AppModel) -> Block {
        let b = Block(kind: BlockKind(rawValue: kindRaw) ?? .link, title: title)
        b.uid = uid; b.urlString = urlString; b.normalizedURL = normalizedURL; b.siteName = siteName; b.note = note
        b.bodyText = bodyText; b.checklistData = checklistData; b.thumbnail = thumbnail; b.thumbnailAspect = thumbnailAspect
        b.pictureChosen = pictureChosen
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

struct DipMenuState: Equatable {
    var canSpin = false
    var hasPick = false
    var inProgress = false
}
