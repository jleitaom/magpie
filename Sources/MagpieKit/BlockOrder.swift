import Foundation

/// How a collection (or All, the Inbox, a tag) lists its blocks (S-065).
public enum BlockOrder: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, quickest, title, site, color, shuffle

    public var id: String { rawValue }

    /// The menu's name.
    public var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .quickest: "Quickest first"
        case .title: "Title A–Z"
        case .site: "Site"
        case .color: "Color"
        case .shuffle: "Shuffle"
        }
    }

    /// The Sort button's short label.
    public var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .quickest: "Quickest"
        case .title: "A–Z"
        case .site: "Site"
        case .color: "Color"
        case .shuffle: "Shuffled"
        }
    }

    public var hint: String {
        switch self {
        case .newest: "Most recently saved"
        case .oldest: "Dig up the forgotten ones"
        case .quickest: "Shortest read or watch"
        case .title: "Alphabetical"
        case .site: "Group by where it’s from"
        case .color: "By the image’s main color"
        case .shuffle: "A new random order each time"
        }
    }
}

/// What ordering needs to know about a block.
public struct OrderItem: Sendable {
    public let id: UUID
    public let createdAt: Date
    public let minutes: Int?
    public let title: String
    public let site: String
    public let color: UInt32?

    public init(id: UUID, createdAt: Date, minutes: Int?, title: String, site: String, color: UInt32?) {
        self.id = id
        self.createdAt = createdAt
        self.minutes = minutes
        self.title = title
        self.site = site
        self.color = color
    }
}

extension BlockOrder {
    /// The ids in this order. Ties fall back to newest first, so the order never jumps around.
    /// `seed` picks the shuffle; the same seed gives the same order.
    public func sorted(_ items: [OrderItem], seed: UInt64 = 0) -> [UUID] {
        func newestFirst(_ a: OrderItem, _ b: OrderItem) -> Bool {
            a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt > b.createdAt
        }
        let ordered: [OrderItem]
        switch self {
        case .newest:
            ordered = items.sorted(by: newestFirst)
        case .oldest:
            ordered = items.sorted { newestFirst($1, $0) }
        case .quickest:
            // Blocks with no known length go last.
            ordered = items.sorted { a, b in
                switch (a.minutes, b.minutes) {
                case let (x?, y?) where x != y: x < y
                case (.some, nil): true
                case (nil, .some): false
                default: newestFirst(a, b)
                }
            }
        case .title:
            ordered = items.sorted { a, b in
                let order = a.title.localizedStandardCompare(b.title)
                return order == .orderedSame ? newestFirst(a, b) : order == .orderedAscending
            }
        case .site:
            ordered = items.sorted { a, b in
                let order = a.site.localizedStandardCompare(b.site)
                return order == .orderedSame ? newestFirst(a, b) : order == .orderedAscending
            }
        case .color:
            // By hue around the color wheel; greys (and blocks with no image) last.
            func hue(_ item: OrderItem) -> Double? { item.color.flatMap { RGB(hex: $0).hue(greyBelow: 0.12) } }
            ordered = items.sorted { a, b in
                switch (hue(a), hue(b)) {
                case let (x?, y?) where x != y: x < y
                case (.some, nil): true
                case (nil, .some): false
                default: newestFirst(a, b)
                }
            }
        case .shuffle:
            ordered = items.sorted(by: newestFirst).map { ($0, Self.mix($0.id, seed)) }.sorted { $0.1 < $1.1 }.map(\.0)
        }
        return ordered.map(\.id)
    }

    /// A stable pseudo-random number from a block and a seed (FNV-1a over the id's bytes, then the seed).
    static func mix(_ id: UUID, _ seed: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325 ^ seed
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        return hash ^ (hash >> 29)
    }
}
