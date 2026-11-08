import AppKit
import MagpieKit
import SwiftData
import UniformTypeIdentifiers

/// Export everything, and read an export back (S-054), so your library is never locked in.
extension AppModel {
    /// File → Export Library: pick where, then write the export folder there.
    func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Magpie writes a folder with library.json, your pictures and bookmarks.html."
        guard panel.runModal() == .OK, let place = panel.url else { return }
        do {
            let folder = try export(into: place)
            flash("Exported to \(folder.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            flash("Couldn’t export: \(error.localizedDescription)")
        }
    }

    /// Writes "Magpie Export <date>" into `place`: library.json (every field, collection, tag and day),
    /// images/<uid>.jpg (every picture) and bookmarks.html (every web link, collections as folders).
    @discardableResult
    func export(into place: URL, now: Date = .now) throws -> URL {
        save()
        let stamp = now.formatted(.iso8601.year().month().day())
        var folder = place.appending(path: "Magpie Export \(stamp)")
        var copy = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = place.appending(path: "Magpie Export \(stamp) \(copy)")
            copy += 1
        }
        let images = folder.appending(path: "images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

        let allBlocks = (try? context.fetch(FetchDescriptor<Block>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var blocks: [LibraryExport.Block] = []
        for block in allBlocks {
            var image: String?
            if let data = block.thumbnail {
                image = "images/\(block.uid.uuidString).jpg"
                try data.write(to: folder.appending(path: image!))
            }
            blocks.append(exported(block, image: image))
        }
        let library = LibraryExport(
            exportedAt: now,
            collections: collections.map(exported),
            tags: tags.map { .init(uid: $0.uid, name: $0.name, colorHex: $0.colorHex, createdAt: $0.createdAt) },
            blocks: blocks,
            days: ((try? context.fetch(FetchDescriptor<DayActivity>(sortBy: [SortDescriptor(\.day)]))) ?? []).map {
                .init(day: $0.day, saved: $0.saved, sorted: $0.sorted, reachedInboxZero: $0.reachedInboxZero,
                      spins: $0.spins, finished: $0.finished)
            })
        try library.json().write(to: folder.appending(path: "library.json"))
        try Data(BookmarkFile.write(bookmarkTree(allBlocks)).utf8).write(to: folder.appending(path: "bookmarks.html"))
        return folder
    }

    /// Every web link as a bookmarks tree: collections (nested) as folders, the rest at the top.
    private func bookmarkTree(_ blocks: [Block]) -> BookmarkFolder {
        func link(_ block: Block) -> BookmarkFolder.Link? {
            guard let url = block.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return .init(url: url, title: block.title.isEmpty ? Links.siteName(url) : block.title, added: block.createdAt)
        }
        func folder(_ collection: BlockCollection, path: String) -> BookmarkFolder {
            let id = path.isEmpty ? collection.name : path + "/" + collection.name
            let children = collections.filter { $0.parent?.uid == collection.uid }
            return BookmarkFolder(id: id, name: collection.name,
                                  links: (collection.blocks ?? []).sorted { $0.createdAt < $1.createdAt }.compactMap(link),
                                  folders: children.map { folder($0, path: id) })
        }
        return BookmarkFolder(id: "", name: "",
                              links: blocks.filter { $0.collection == nil }.compactMap(link),
                              folders: collections.filter { $0.parent == nil }.map { folder($0, path: "") })
    }

    private func exported(_ collection: BlockCollection) -> LibraryExport.Collection {
        .init(uid: collection.uid, name: collection.name, colorHex: collection.colorHex, sortIndex: collection.sortIndex,
              isPinned: collection.isPinned, pinIndex: collection.pinIndex, createdAt: collection.createdAt,
              parent: collection.parent?.uid, sortOrder: collection.sortOrderRaw, viewMode: collection.viewModeRaw,
              shuffleSeed: collection.shuffleSeed, expiryDays: collection.defaultExpiryDays)
    }

    private func exported(_ block: Block, image: String?) -> LibraryExport.Block {
        .init(uid: block.uid, kind: block.kindRaw, url: block.urlString, normalizedURL: block.normalizedURL, title: block.title,
              siteName: block.siteName, note: block.note, bodyText: block.bodyText,
              checklist: block.checklist.map { .init(id: $0.id, text: $0.text, done: $0.done) },
              image: image, imageAspect: block.thumbnailAspect, colorHex: block.colorHex, status: block.statusRaw,
              statusBeforeArchive: block.statusBeforeArchiveRaw, createdAt: block.createdAt, openedAt: block.openedAt,
              finishedAt: block.finishedAt, expiresAt: block.expiresAt, expiredAt: block.expiredAt, lastShownAt: block.lastShownAt,
              collection: block.collection?.uid, tags: (block.tags ?? []).map(\.uid), minutes: block.minutes, price: block.price,
              currency: block.currency, isRecipe: block.isRecipe, pile: block.pileRaw, timesSkipped: block.timesSkipped,
              ocrText: block.ocrText, sortIndex: block.sortIndex)
    }

    // MARK: Reading an export back

    /// File → Import Magpie Export: pick the library.json of an export.
    func chooseExportToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose library.json inside a Magpie Export folder."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let added = try importExport(file)
            flash(added == 0 ? "Everything in that export is already here" : "Imported \(added) blocks")
        } catch {
            flash("Couldn’t read that export: \(error.localizedDescription)")
        }
    }

    /// Reads an export back. Anything already in the library (same id) is left as it is, so
    /// importing twice changes nothing. Returns how many blocks were added.
    @discardableResult
    func importExport(_ file: URL) throws -> Int {
        let library = try LibraryExport.read(Data(contentsOf: file))
        let folder = file.deletingLastPathComponent()
        var collectionsByID = Dictionary(collections.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        for item in library.collections where collectionsByID[item.uid] == nil {
            let made = BlockCollection(name: item.name, colorHex: item.colorHex, sortIndex: item.sortIndex)
            made.uid = item.uid
            made.isPinned = item.isPinned && pinnedCollections.count < Pins.limit
            made.pinIndex = item.pinIndex
            made.createdAt = item.createdAt
            made.sortOrderRaw = item.sortOrder
            made.viewModeRaw = item.viewMode
            made.shuffleSeed = item.shuffleSeed
            made.defaultExpiryDays = item.expiryDays
            context.insert(made)
            collectionsByID[item.uid] = made
        }
        for item in library.collections where item.parent != nil {
            if let child = collectionsByID[item.uid], child.parent == nil { child.parent = collectionsByID[item.parent!] }
        }
        var tagsByID = Dictionary(tags.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        for item in library.tags where tagsByID[item.uid] == nil {
            let made = Tag(name: item.name, colorHex: item.colorHex)
            made.uid = item.uid
            made.createdAt = item.createdAt
            context.insert(made)
            tagsByID[item.uid] = made
        }
        let existing = Set(((try? context.fetch(FetchDescriptor<Block>())) ?? []).map(\.uid))
        var added = 0
        for item in library.blocks where !existing.contains(item.uid) {
            let block = Block(kind: BlockKind(rawValue: item.kind) ?? .link, title: item.title)
            block.uid = item.uid
            block.urlString = item.url
            block.normalizedURL = item.normalizedURL
            block.siteName = item.siteName
            block.note = item.note
            block.bodyText = item.bodyText
            block.checklist = item.checklist.map { ChecklistItem(id: $0.id, text: $0.text, done: $0.done) }
            block.thumbnail = item.image.flatMap { try? Data(contentsOf: folder.appending(path: $0)) }
            block.thumbnailAspect = item.imageAspect
            block.colorHex = item.colorHex
            block.statusRaw = item.status
            block.statusBeforeArchiveRaw = item.statusBeforeArchive
            block.createdAt = item.createdAt
            block.openedAt = item.openedAt
            block.finishedAt = item.finishedAt
            block.expiresAt = item.expiresAt
            block.expiredAt = item.expiredAt
            block.lastShownAt = item.lastShownAt
            block.collection = item.collection.flatMap { collectionsByID[$0] }
            block.tags = item.tags.compactMap { tagsByID[$0] }
            block.minutes = item.minutes
            block.price = item.price
            block.currency = item.currency
            block.isRecipe = item.isRecipe
            block.pileRaw = item.pile
            block.timesSkipped = item.timesSkipped
            block.ocrText = item.ocrText
            block.sortIndex = item.sortIndex
            block.enrichRaw = EnrichState.done.rawValue
            context.insert(block)
            added += 1
        }
        let days = Set(((try? context.fetch(FetchDescriptor<DayActivity>())) ?? []).map(\.day))
        for item in library.days where !days.contains(item.day) {
            let day = DayActivity(day: item.day)
            day.saved = item.saved
            day.sorted = item.sorted
            day.reachedInboxZero = item.reachedInboxZero
            day.spins = item.spins
            day.finished = item.finished
            context.insert(day)
        }
        save()
        refreshStreak()
        refreshDipStats()
        return added
    }
}
