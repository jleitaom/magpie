import Testing
@testable import MagpieKit

struct StreakTests {
    func zero(_ day: Int, saved: Int = 3) -> DayRecord { DayRecord(day: day, saved: saved, reachedInboxZero: true) }
    func missed(_ day: Int, saved: Int = 2) -> DayRecord { DayRecord(day: day, saved: saved, reachedInboxZero: false) }
    func quiet(_ day: Int) -> DayRecord { DayRecord(day: day, saved: 0, reachedInboxZero: false) }

    @Test("The streak counts days in a row with Inbox zero")
    func inARow() {
        #expect(Streak.days([zero(98), zero(99), zero(100)], today: 100) == 3)
        #expect(Streak.days([], today: 100) == 0)
    }

    @Test("A day with nothing new saved doesn't break it")
    func quietDay() {
        #expect(Streak.days([zero(97), quiet(98), zero(99), zero(100)], today: 100) == 3)
        // No record at all means nothing was saved that day.
        #expect(Streak.days([zero(96), zero(97), zero(100)], today: 100) == 3)
    }

    @Test("A day with saves that never reached zero breaks it")
    func broken() {
        #expect(Streak.days([zero(96), zero(97), missed(98), zero(99), zero(100)], today: 100) == 2)
        #expect(Streak.days([zero(98), missed(99)], today: 100) == 0)
    }

    @Test("Today doesn't break it before it's over")
    func todayInProgress() {
        #expect(Streak.days([zero(98), zero(99), missed(100)], today: 100) == 2)
        #expect(Streak.days([zero(98), zero(99), zero(100)], today: 100) == 3)
    }

    @Test("Two records for the same day count once")
    func duplicateDay() {
        #expect(Streak.days([missed(100), zero(100), zero(99)], today: 100) == 2)
    }

    @Test("The ring fills over 7 days", arguments: [(0, 0.0), (1, 1.0 / 7), (6, 6.0 / 7), (7, 1.0), (30, 1.0)])
    func ring(days: Int, fill: Double) {
        #expect(Streak.ringFill(days) == fill)
    }
}
