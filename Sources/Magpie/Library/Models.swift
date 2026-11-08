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
    /// The page is a schema.org Recipe (for the Cook pile).
    var isRecipe: Bool = false
    /// A pile chosen by hand, over the one worked out from the kind (S-069).
    var pileRaw: String?
    /// How often Lucky Dip's "Not today" passed on it; it comes up less often (S-071).
    var timesSkipped: Int = 0
    var finishedAt: Date?
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

    var pileOverride: Pile? {
        get { pileRaw.flatMap(Pile.init(rawValue:)) }
        set { pileRaw = newValue?.rawValue }
    }

    /// The Lucky Dip pile it's on, or nil (notes, products, images…).
    var pile: Pile? { Pile.of(kind: kindRaw, site: siteName, isRecipe: isRecipe, override: pileOverride) }

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

/// What happened on one day, for the Inbox zero streak (and later Lucky Dip's re-spins).
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

    init(day: Int) {
        self.day = day
    }

    static func number(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }
}
