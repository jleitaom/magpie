import Foundation

/// What you'd do with a block. Worked out from its kind, not filed by hand (a block can override it).
public enum Pile: String, CaseIterable, Identifiable, Sendable {
    case read, watch, listen, cook, visit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .read: "Read"
        case .watch: "Watch"
        case .listen: "Listen"
        case .cook: "Cook"
        case .visit: "Visit"
        }
    }

    /// The button that commits to a pick.
    public var startVerb: String {
        switch self {
        case .read: "Start reading"
        case .watch: "Start watching"
        case .listen: "Put it on"
        case .cook: "Cook it"
        case .visit: "Go there"
        }
    }

    /// Which pile a block is on: its override if it has one, else from its kind and site.
    /// Notes, checklists, products, images and files are on no pile.
    public static func of(kind: String, site: String, isRecipe: Bool, override: Pile?) -> Pile? {
        if let override { return override }
        switch kind {
        case "note", "checklist", "product", "image", "file": return nil
        case "place": return .visit
        default: break
        }
        if isRecipe { return .cook }
        let site = site.lowercased()
        let music = ["discogs.com", "bandcamp.com", "music.apple.com", "open.spotify.com", "spotify.com", "soundcloud.com"]
        if music.contains(where: { site == $0 || site.hasSuffix("." + $0) }) { return .listen }
        if kind == "video" { return .watch }
        return .read
    }
}

/// One block Lucky Dip could pick.
public struct DipCandidate: Equatable, Sendable {
    public let id: UUID
    public let minutes: Int?
    public let timesSkipped: Int

    public init(id: UUID, minutes: Int?, timesSkipped: Int) {
        self.id = id
        self.minutes = minutes
        self.timesSkipped = timesSkipped
    }
}

public enum LuckyDip {
    /// Spins a day: the first one, then this many re-spins.
    public static let respinsPerDay = 2

    /// The blocks that fit the time you have. With a limit, blocks of unknown length are left out.
    public static func fitting(_ candidates: [DipCandidate], maxMinutes: Int?) -> [DipCandidate] {
        guard let maxMinutes else { return candidates }
        return candidates.filter { ($0.minutes ?? .max) <= maxMinutes }
    }

    /// A random pick from the blocks that fit, weighted down by how often each was skipped
    /// (weight 1 / (1 + skips)). `avoiding` is the current pick, never picked again when there's another.
    public static func pick<R: RandomNumberGenerator>(from candidates: [DipCandidate], maxMinutes: Int?,
                                                      avoiding: UUID? = nil, using random: inout R) -> UUID? {
        var pool = fitting(candidates, maxMinutes: maxMinutes)
        if pool.count > 1, let avoiding { pool.removeAll { $0.id == avoiding } }
        guard !pool.isEmpty else { return nil }
        let weights = pool.map { 1.0 / Double(1 + max($0.timesSkipped, 0)) }
        var roll = Double.random(in: 0..<weights.reduce(0, +), using: &random)
        for (candidate, weight) in zip(pool, weights) {
            if roll < weight { return candidate.id }
            roll -= weight
        }
        return pool.last?.id
    }

    public static func pick(from candidates: [DipCandidate], maxMinutes: Int?, avoiding: UUID? = nil) -> UUID? {
        var random = SystemRandomNumberGenerator()
        return pick(from: candidates, maxMinutes: maxMinutes, avoiding: avoiding, using: &random)
    }

    /// Re-spins left today, from the spins already made today (the first spin is free).
    public static func respinsLeft(spinsToday: Int) -> Int {
        max(0, respinsPerDay - max(spinsToday - 1, 0))
    }

    /// True when another spin is allowed today.
    public static func canSpin(spinsToday: Int) -> Bool {
        spinsToday < 1 + respinsPerDay
    }

    /// After this many "Not today"s, the block's details ask "Still want this?".
    public static let skipsBeforeAsking = 3

    /// The dip streak: days in a row with at least one finished pick. Today doesn't break it
    /// before it's over.
    public static func streak(finishedOn days: Set<Int>, today: Int) -> Int {
        var day = days.contains(today) ? today : today - 1
        var count = 0
        while days.contains(day) {
            count += 1
            day -= 1
        }
        return count
    }

    /// The first day (a day number) of the Monday-to-Sunday week holding `today`.
    /// `weekday` is today's ISO weekday: 1 = Monday … 7 = Sunday.
    public static func weekStart(today: Int, weekday: Int) -> Int {
        today - (min(max(weekday, 1), 7) - 1)
    }

    /// "3 h 10 min", "45 min", or "" for nothing known.
    public static func totalTime(_ minutes: [Int?]) -> String {
        let total = minutes.compactMap { $0 }.reduce(0, +)
        return total == 0 ? "" : Badges.minutes(total)
    }
}
