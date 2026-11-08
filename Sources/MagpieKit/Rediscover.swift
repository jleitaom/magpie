import Foundation

/// One block Rediscover could show.
public struct RediscoverCandidate: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let openedAt: Date?
    public let lastShownAt: Date?
    public let timesSkipped: Int

    public init(id: UUID, createdAt: Date, openedAt: Date?, lastShownAt: Date?, timesSkipped: Int) {
        self.id = id
        self.createdAt = createdAt
        self.openedAt = openedAt
        self.lastShownAt = lastShownAt
        self.timesSkipped = timesSkipped
    }
}

/// Rediscover (S-020): a few random old saves a day, to keep or archive.
public enum Rediscover {
    public static let perDay = 5
    /// A block counts as old when it hasn't been opened (or saved, if never opened) for this long,
    /// and wasn't shown by Rediscover in that time either.
    public static let restDays = 14

    public static func isEligible(_ candidate: RediscoverCandidate, now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(restDays) * 86_400)
        let lastTouched = candidate.openedAt ?? candidate.createdAt
        return lastTouched <= cutoff && (candidate.lastShownAt.map { $0 <= cutoff } ?? true)
    }

    /// Today's picks: up to 5 eligible blocks, drawn without repeats, weighted toward blocks
    /// skipped less often (weight 1 / (1 + skips)).
    public static func pick<R: RandomNumberGenerator>(from candidates: [RediscoverCandidate], now: Date,
                                                      count: Int = perDay, using random: inout R) -> [UUID] {
        var pool = candidates.filter { isEligible($0, now: now) }
        var picked: [UUID] = []
        while picked.count < count, !pool.isEmpty {
            let weights = pool.map { 1.0 / Double(1 + max($0.timesSkipped, 0)) }
            var roll = Double.random(in: 0..<weights.reduce(0, +), using: &random)
            var index = pool.count - 1
            for (offset, weight) in weights.enumerated() {
                if roll < weight { index = offset; break }
                roll -= weight
            }
            picked.append(pool.remove(at: index).id)
        }
        return picked
    }

    public static func pick(from candidates: [RediscoverCandidate], now: Date, count: Int = perDay) -> [UUID] {
        var random = SystemRandomNumberGenerator()
        return pick(from: candidates, now: now, count: count, using: &random)
    }
}

/// Collections whose blocks expire (S-021).
public enum Expiry {
    /// Choices offered for a collection.
    public static let choices = [7, 14, 30, 90]
    /// Cards show a warning this many days ahead.
    public static let warningDays = 3

    /// When a block added now expires, or nil when the collection doesn't expire blocks.
    public static func date(addedAt: Date, days: Int?) -> Date? {
        guard let days, days > 0 else { return nil }
        return addedAt.addingTimeInterval(Double(days) * 86_400)
    }

    public static func isDue(_ expiresAt: Date?, now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }

    /// "expires today", "expires in 1 d" … within the warning window, else nil.
    public static func label(_ expiresAt: Date?, now: Date) -> String? {
        guard let expiresAt, expiresAt > now else { return nil }
        let days = Int((expiresAt.timeIntervalSince(now) / 86_400).rounded(.up))
        guard days <= warningDays else { return nil }
        return days <= 0 ? "expires today" : "expires in \(days) d"
    }
}

/// Dock drops (S-041): a quick drop saves quietly; holding the item on the icon until the Dock
/// brings Magpie forward (spring-loading) opens it.
public enum DockDrop {
    /// Magpie became active this recently before the drop: the drop itself brought it forward.
    public static let quickDropWindow: TimeInterval = 1.0

    /// True when Magpie should step back after saving: it was launched by the drop, or the
    /// drop is what activated it. False when it was already in front (you waited on the icon,
    /// or were using it).
    public static func shouldStepBack(activeSince: Date?, wasRunning: Bool, now: Date) -> Bool {
        guard wasRunning, let activeSince else { return true }
        return now.timeIntervalSince(activeSince) < quickDropWindow
    }
}
