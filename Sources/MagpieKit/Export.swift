import Foundation

/// Everything in a Magpie library, as plain values that encode to readable JSON (S-054).
/// Pictures are separate files ("images/<uid>.jpg"), named in `image`.
public struct LibraryExport: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = LibraryExport.currentVersion
    public var exportedAt: Date
    public var collections: [Collection]
    public var tags: [Tag]
    public var blocks: [Block]
    public var days: [Day]

    public init(exportedAt: Date, collections: [Collection], tags: [Tag], blocks: [Block], days: [Day]) {
        self.exportedAt = exportedAt
        self.collections = collections
        self.tags = tags
        self.blocks = blocks
        self.days = days
    }

    public struct Collection: Codable, Equatable, Sendable {
        public var uid: UUID
        public var name: String
        public var colorHex: Int
        public var sortIndex: Double
        public var isPinned: Bool
        public var pinIndex: Int
        public var createdAt: Date
        public var parent: UUID?
        public var sortOrder: String?
        public var viewMode: String?
        public var shuffleSeed: Int
        public var expiryDays: Int?

        public init(uid: UUID, name: String, colorHex: Int, sortIndex: Double, isPinned: Bool, pinIndex: Int, createdAt: Date,
                    parent: UUID?, sortOrder: String?, viewMode: String?, shuffleSeed: Int, expiryDays: Int?) {
            self.uid = uid; self.name = name; self.colorHex = colorHex; self.sortIndex = sortIndex; self.isPinned = isPinned
            self.pinIndex = pinIndex; self.createdAt = createdAt; self.parent = parent; self.sortOrder = sortOrder
            self.viewMode = viewMode; self.shuffleSeed = shuffleSeed; self.expiryDays = expiryDays
        }
    }

    public struct Tag: Codable, Equatable, Sendable {
        public var uid: UUID
        public var name: String
        public var colorHex: Int
        public var createdAt: Date

        public init(uid: UUID, name: String, colorHex: Int, createdAt: Date) {
            self.uid = uid; self.name = name; self.colorHex = colorHex; self.createdAt = createdAt
        }
    }

    public struct ChecklistItem: Codable, Equatable, Sendable {
        public var id: UUID
        public var text: String
        public var done: Bool

        public init(id: UUID, text: String, done: Bool) { self.id = id; self.text = text; self.done = done }
    }

    public struct Block: Codable, Equatable, Sendable {
        public var uid: UUID
        public var kind: String
        public var url: String?
        public var normalizedURL: String?
        public var title: String
        public var siteName: String
        public var note: String
        public var bodyText: String
        public var checklist: [ChecklistItem]
        /// The picture's file in the export folder ("images/<uid>.jpg"), if it has one.
        public var image: String?
        public var imageAspect: Double
        public var colorHex: Int?
        public var status: String
        public var statusBeforeArchive: String?
        public var createdAt: Date
        public var openedAt: Date?
        public var finishedAt: Date?
        public var expiresAt: Date?
        public var expiredAt: Date?
        public var lastShownAt: Date?
        public var collection: UUID?
        public var tags: [UUID]
        public var minutes: Int?
        public var price: Double?
        public var currency: String?
        public var isRecipe: Bool
        public var pile: String?
        public var timesSkipped: Int
        public var ocrText: String?
        public var sortIndex: Double
        /// The picture was chosen by hand. Missing in exports from before 1.1.
        public var pictureChosen: Bool?
        /// The kind was chosen by hand (#9). Missing in exports from before 1.2.
        public var kindChosen: Bool?

        public init(uid: UUID, kind: String, url: String?, normalizedURL: String?, title: String, siteName: String, note: String,
                    bodyText: String, checklist: [ChecklistItem], image: String?, imageAspect: Double, colorHex: Int?,
                    status: String, statusBeforeArchive: String?, createdAt: Date, openedAt: Date?, finishedAt: Date?,
                    expiresAt: Date?, expiredAt: Date?, lastShownAt: Date?, collection: UUID?, tags: [UUID], minutes: Int?,
                    price: Double?, currency: String?, isRecipe: Bool, pile: String?, timesSkipped: Int, ocrText: String?,
                    sortIndex: Double, pictureChosen: Bool? = nil, kindChosen: Bool? = nil) {
            self.uid = uid; self.kind = kind; self.url = url; self.normalizedURL = normalizedURL; self.title = title
            self.siteName = siteName; self.note = note; self.bodyText = bodyText; self.checklist = checklist; self.image = image
            self.imageAspect = imageAspect; self.colorHex = colorHex; self.status = status; self.statusBeforeArchive = statusBeforeArchive
            self.createdAt = createdAt; self.openedAt = openedAt; self.finishedAt = finishedAt; self.expiresAt = expiresAt
            self.expiredAt = expiredAt; self.lastShownAt = lastShownAt; self.collection = collection; self.tags = tags
            self.minutes = minutes; self.price = price; self.currency = currency; self.isRecipe = isRecipe; self.pile = pile
            self.timesSkipped = timesSkipped; self.ocrText = ocrText; self.sortIndex = sortIndex; self.pictureChosen = pictureChosen
            self.kindChosen = kindChosen
        }
    }

    public struct Day: Codable, Equatable, Sendable {
        public var day: Int
        public var saved: Int
        public var sorted: Int
        public var reachedInboxZero: Bool
        public var spins: Int
        public var finished: Int

        public init(day: Int, saved: Int, sorted: Int, reachedInboxZero: Bool, spins: Int, finished: Int) {
            self.day = day; self.saved = saved; self.sorted = sorted; self.reachedInboxZero = reachedInboxZero
            self.spins = spins; self.finished = finished
        }
    }

    /// Readable JSON: sorted keys, indented, dates as ISO 8601 with fractions so nothing is lost.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.dateFormat.string(from: date))
        }
        return try encoder.encode(self)
    }

    public static func read(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = dateFormat.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(text)"))
            }
            return date
        }
        return try decoder.decode(LibraryExport.self, from: data)
    }

    nonisolated(unsafe) private static let dateFormat: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()
}

extension BookmarkFile {
    /// The bookmarks file browsers import (the format they export): collections as folders,
    /// links outside any collection at the top. Only web links are written.
    public static func write(_ root: BookmarkFolder, title: String = "Magpie") -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func links(_ items: [BookmarkFolder.Link], indent: String) -> [String] {
            items.map { link in
                let date = link.added.map { " ADD_DATE=\"\(Int($0.timeIntervalSince1970))\"" } ?? ""
                return "\(indent)<DT><A HREF=\"\(escape(link.url.absoluteString))\"\(date)>\(escape(link.title))</A>"
            }
        }
        func writeFolder(_ folder: BookmarkFolder, _ indent: String) -> [String] {
            var out = [indent + "<DT><H3>" + escape(folder.name) + "</H3>", indent + "<DL><p>"]
            out += links(folder.links, indent: indent + "    ")
            for child in folder.folders { out += writeFolder(child, indent + "    ") }
            out.append(indent + "</DL><p>")
            return out
        }
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file. It will be read and overwritten. DO NOT EDIT! -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>" + escape(title) + "</H1>",
            "<DL><p>",
        ]
        for child in root.folders { lines += writeFolder(child, "    ") }
        lines += links(root.links, indent: "    ")
        lines += ["</DL><p>", ""]
        return lines.joined(separator: "\n")
    }
}
