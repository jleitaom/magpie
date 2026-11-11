import Foundation
import MagpieKit
import SwiftData

// The data. Written to CloudKit's rules so iCloud sync can be turned on later
// without a migration: every property has a default or is optional, every
// relationship is optional with an inverse, no unique constraints (duplicates
// are found in code by `normalizedURL`), order is a Double.

enum BlockKind: String, CaseIterable, Codable {
    case link, video, product, place, image, file, note, checklist

    var label: String {
        switch self {
        case .link: "Link"
        case .video: "Video"
        case .product: "Product"
        case .place: "Place"
        case .image: "Image"
        case .file: "File"
        case .note: "Note"
        case .checklist: "Checklist"
        }
    }
}

enum BlockStatus: String, Codable {
    /// inProgress: committed to from Lucky Dip and not finished yet.
    case inbox, kept, inProgress, done, archived
}

/// Where a block's preview stands: waiting for the network, filled in, or given up on.
enum EnrichState: String, Codable {
    case pending, done, failed
}

struct ChecklistItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var done = false
}

@Model
final class Block {
    var uid: UUID = UUID()
    var kindRaw: String = BlockKind.link.rawValue
    var urlString: String?
    var normalizedURL: String?
    var title: String = ""
    var siteName: String = ""
    var note: String = ""
    /// A note's text.
    var bodyText: String = ""
    var checklistData: Data?
    @Attribute(.externalStorage) var thumbnail: Data?
    /// Width / height of the thumbnail, for laying out the Gallery before images load.
    var thumbnailAspect: Double = 0
    /// The picture was chosen by hand (Choose Picture…, #2), so refreshing the link keeps it.
    var pictureChosen: Bool = false
    /// The thumbnail's main color as 0xRRGGBB (stored as Int for SwiftData).
    var colorHex: Int?
    var statusRaw: String = BlockStatus.inbox.rawValue
    var enrichRaw: String = EnrichState.done.rawValue
    var createdAt: Date = Date.now
    var openedAt: Date?
    var collection: BlockCollection?
    /// Watch time for a video, read time for an article (S-063).
    var minutes: Int?
    /// A product's price when it was saved, in `currency` (an ISO code like "EUR").
    var price: Double?
    var currency: String?
    /// The page is a schema.org Recipe (Lucky Dip says "Cook it").
    var isRecipe: Bool = false
    /// No longer used: Lucky Dip had piles until 1.1 (#3), now it picks from collections. Kept so
    /// existing libraries and exports still open, and so the model stays CloudKit-safe.
    var pileRaw: String?
    /// How often Lucky Dip's "Not today" passed on it; it comes up less often (S-071).
    var timesSkipped: Int = 0
    var finishedAt: Date?
    /// Archive (S-022): the status before archiving, so Unarchive puts it back.
    var statusBeforeArchiveRaw: String?
    /// Expiry (S-021): when it expires, and when it did (an expired block is archived, never deleted).
    var expiresAt: Date?
    var expiredAt: Date?
    /// Rediscover (S-020): when it last came up there.
    var lastShownAt: Date?
    /// Text read from its image with Vision, for search (S-031).
    var ocrText: String?
    /// Your own order, when a place is sorted by Manual (S-066).
    var sortIndex: Double = 0
    /// Tags (S-014). Many-to-many, optional on both sides for CloudKit.
    @Relationship(deleteRule: .nullify, inverse: \Tag.blocks) var tags: [Tag]? = []

    init(kind: BlockKind, title: String = "") {
        self.kindRaw = kind.rawValue
        self.title = title
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .link }
        set { kindRaw = newValue.rawValue }
    }

    var status: BlockStatus {
        get { BlockStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    var enrich: EnrichState {
        get { EnrichState(rawValue: enrichRaw) ?? .done }
        set { enrichRaw = newValue.rawValue }
    }

    var url: URL? { urlString.flatMap(URL.init(string:)) }

    var checklist: [ChecklistItem] {
        get { checklistData.flatMap { try? JSONDecoder().decode([ChecklistItem].self, from: $0) } ?? [] }
        set { checklistData = try? JSONEncoder().encode(newValue) }
    }

    var tint: UInt32? { colorHex.map { UInt32(truncatingIfNeeded: $0) } }

    /// Deleted (or detached from its library). A view still on screen for a moment after a
    /// delete must not read it: SwiftData stops the app when a deleted block's picture is read.
    var isGone: Bool { isDeleted || modelContext == nil }

    /// What Lucky Dip's start button says for it: "Start watching", "Cook it", "Go there"…
    var startVerb: String { LuckyDip.startVerb(kind: kindRaw, site: siteName, isRecipe: isRecipe) }

    /// Everything search looks in, folded once: title, note, text, link, site, tags, text in the image.
    var searchIndex: String {
        Search.index([title, note, bodyText, urlString, siteName, ocrText, collection?.name]
                     + (tags ?? []).map(\.name) + checklist.map(\.text))
    }

    /// The card's badge: the price for a product, else the watch or read time.
    var badge: String? {
        if let price { return Badges.price(price, currency: currency) }
        return minutes.map(Badges.minutes)
    }
}

/// A named place for blocks (Watch later, Shopping…). Called BlockCollection in code
/// because Swift already has a `Collection`.
@Model
final class BlockCollection {
    var uid: UUID = UUID()
    var name: String = ""
    var colorHex: Int = 0x7FD9D3
    var sortIndex: Double = 0
    var isPinned: Bool = false
    var pinIndex: Int = 0
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Block.collection) var blocks: [Block]? = []
    /// The collection this one is nested in, or nil at the top level.
    var parent: BlockCollection?
    /// How this collection lists its blocks, and in which view (S-065, S-067). Nil: the defaults.
    var sortOrderRaw: String?
    var viewModeRaw: String?
    var shuffleSeed: Int = 0
    /// Blocks added from now on expire after this many days (S-021). Nil: never.
    var defaultExpiryDays: Int?
    @Relationship(deleteRule: .nullify, inverse: \BlockCollection.parent) var children: [BlockCollection]? = []

    init(name: String, colorHex: Int, sortIndex: Double) {
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

/// A label on any number of blocks, across collections (S-014). Names are case-insensitive:
/// "Jazz" and "jazz" are one tag (checked in code, no unique constraint, for CloudKit).
@Model
final class Tag {
    var uid: UUID = UUID()
    var name: String = ""
    var colorHex: Int = 0x7FD9D3
    var createdAt: Date = Date.now
    var blocks: [Block]? = []

    init(name: String, colorHex: Int) {
        self.name = name
        self.colorHex = colorHex
    }
}

/// Colors offered for new collections, from the mockup.
enum CollectionColors {
    static let all: [Int] = [0x7FD9D3, 0xE8A27A, 0xE8CF8A, 0xA8D5A2, 0x8FB5E8, 0xC9A8E8, 0xE88FB0, 0xA1A1A8]
}

/// What happened on one day, Inbox zero and Lucky Dip's re-spins and finished picks.
/// One record per day; duplicates (from sync, later) are merged when read.
@Model
final class DayActivity {
    /// Days counted in the user's calendar (`DayActivity.number(for:)`), so consecutive days differ by 1.
    var day: Int = 0
    var saved: Int = 0
    var sorted: Int = 0
    var reachedInboxZero: Bool = false
    /// Lucky Dip spins today (the first is free, then 2 re-spins), picks finished, and today's pick.
    var spins: Int = 0
    var finished: Int = 0
    var pickUID: UUID?
    /// Rediscover's five for the day (ids joined by commas) and how many are done.
    var rediscoverRaw: String?
    var rediscoverDone: Int = 0

    init(day: Int) {
        self.day = day
    }

    static func number(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }
}
