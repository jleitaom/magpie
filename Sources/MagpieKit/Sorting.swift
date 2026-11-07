import Foundation

/// One Sort Inbox run: the queue of Inbox blocks and what happened to each.
/// The current block is the first in the queue. Skip sends it to the back, never to the start.
public struct SortSession: Equatable, Sendable {
    public enum Outcome: Sendable { case kept, done, deleted }

    public private(set) var queue: [UUID]
    public private(set) var sorted = 0
    public private(set) var kept = 0
    public private(set) var done = 0
    public private(set) var deleted = 0

    public init(inbox: [UUID]) {
        queue = inbox
    }

    public var current: UUID? { queue.first }
    /// The blocks after the current one, for the cards stacked behind it.
    public var upNext: ArraySlice<UUID> { queue.dropFirst() }
    public var left: Int { queue.count }
    /// 0...1: sorted out of everything this run has seen.
    public var progress: Double {
        let total = sorted + left
        return total == 0 ? 1 : Double(sorted) / Double(total)
    }

    /// The current block goes to the back of the queue.
    public mutating func skip() {
        guard queue.count > 1 else { return }
        queue.append(queue.removeFirst())
    }

    /// The current block was moved, marked done or deleted: count it and go to the next.
    public mutating func finish(_ outcome: Outcome) {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        sorted += 1
        switch outcome {
        case .kept: kept += 1
        case .done: done += 1
        case .deleted: deleted += 1
        }
    }

    /// Keeps the queue in step with the Inbox: blocks that left it (moved elsewhere, deleted)
    /// drop out, and new ones (saved meanwhile, or brought back by Undo) join at the back.
    public mutating func sync(inbox: [UUID]) {
        let now = Set(inbox)
        let known = Set(queue)
        queue = queue.filter(now.contains) + inbox.filter { !known.contains($0) }
    }
}

/// Which collection a block probably belongs in, from its site and kind.
public enum SortSuggestion {
    /// What a block is for, guessed from its site and kind.
    public enum Purpose: String, CaseIterable, Sendable {
        case watch, shopping, listen, visit, cook, ideas, read
    }

    public static func purpose(site: String, kind: String, title: String = "") -> Purpose {
        let site = site.lowercased()
        let title = title.lowercased()
        func on(_ hosts: [String]) -> Bool { hosts.contains { site == $0 || site.hasSuffix("." + $0) } }
        if kind == "video" || on(["youtube.com", "youtu.be", "vimeo.com", "twitch.tv", "netflix.com", "tiktok.com"]) { return .watch }
        if kind == "place" || site.hasPrefix("maps.") || on(["maps.apple.com", "maps.google.com", "airbnb.com", "booking.com"]) { return .visit }
        if on(["discogs.com", "bandcamp.com", "spotify.com", "music.apple.com", "soundcloud.com"]) { return .listen }
        if title.contains("recipe") || on(["seriouseats.com", "bbcgoodfood.com", "cooking.nytimes.com", "allrecipes.com"]) { return .cook }
        if on(["etsy.com", "amazon.com", "ebay.com", "hay.dk", "nordicnest.com", "ikea.com", "muji.com", "zara.com"])
            || site.contains("shop") || site.contains("store") { return .shopping }
        if kind == "note" || kind == "checklist" || kind == "image" || on(["pinterest.com", "dribbble.com", "behance.net", "are.na"]) { return .ideas }
        return .read
    }

    /// Words in a collection's name that fit each purpose.
    static let words: [Purpose: [String]] = [
        .watch: ["watch", "video", "film", "movie", "youtube"],
        .shopping: ["shop", "buy", "wish", "gift", "store"],
        .listen: ["vinyl", "music", "record", "listen", "album"],
        .visit: ["trip", "travel", "place", "visit", "map"],
        .cook: ["recipe", "cook", "food", "eat"],
        .ideas: ["idea", "inspiration", "mood"],
        .read: ["read", "article", "book"],
    ]

    /// The suggested collection: the first whose name fits the block's purpose, else the
    /// collection used last for the same site, else none.
    public static func collection(site: String, kind: String, title: String = "",
                                  collections: [(id: UUID, name: String)], lastUsedForSite: UUID?) -> UUID? {
        let fitting = words[purpose(site: site, kind: kind, title: title)] ?? []
        if let match = collections.first(where: { entry in fitting.contains { entry.name.lowercased().contains($0) } }) {
            return match.id
        }
        if let lastUsedForSite, collections.contains(where: { $0.id == lastUsedForSite }) { return lastUsedForSite }
        return nil
    }
}
