import Foundation

/// One day's activity, as the streak rule needs it. `day` is a day number (days counted
/// in the user's calendar), so consecutive days differ by 1.
public struct DayRecord: Equatable, Sendable {
    public let day: Int
    public let saved: Int
    public let reachedInboxZero: Bool

    public init(day: Int, saved: Int, reachedInboxZero: Bool) {
        self.day = day
        self.saved = saved
        self.reachedInboxZero = reachedInboxZero
    }
}

/// The Inbox zero streak: days in a row on which the Inbox reached zero.
public enum Streak {
    /// The ring in the top bar fills over a week.
    public static let ringDays = 7

    /// Counts back from today. A day that reached Inbox zero adds one. A day with nothing new
    /// saved (or no record at all) neither adds nor breaks. A day with saves that never reached
    /// zero breaks the streak, except today, which isn't over yet.
    public static func days(_ records: [DayRecord], today: Int) -> Int {
        let byDay = Dictionary(records.map { ($0.day, $0) }, uniquingKeysWith: { first, second in
            DayRecord(day: first.day, saved: first.saved + second.saved,
                      reachedInboxZero: first.reachedInboxZero || second.reachedInboxZero)
        })
        guard let earliest = byDay.keys.min() else { return 0 }
        var count = 0
        var day = today
        while day >= earliest {
            if let record = byDay[day] {
                if record.reachedInboxZero {
                    count += 1
                } else if record.saved > 0, day != today {
                    break
                }
            }
            day -= 1
        }
        return count
    }

    /// 0...1: how full the top bar ring is.
    public static func ringFill(_ days: Int) -> Double {
        Double(min(max(days, 0), ringDays)) / Double(ringDays)
    }
}
