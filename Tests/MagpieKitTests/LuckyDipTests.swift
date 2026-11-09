import Foundation
import Testing
@testable import MagpieKit

struct StartVerbTests {
    @Test("The start button says what you'll do, from the block's kind and site", arguments: [
        ("link", "paulgraham.com", false, "Start reading"),
        ("video", "youtube.com", false, "Start watching"),
        ("place", "maps.apple.com", false, "Go there"),
        ("link", "seriouseats.com", true, "Cook it"),
        ("link", "discogs.com", false, "Put it on"),
        ("link", "open.spotify.com", false, "Put it on"),
        ("product", "hay.dk", false, "Have a look"),
        ("note", "Note", false, "Open it"),
        ("checklist", "Checklist", false, "Open it"),
    ])
    func verb(kind: String, site: String, recipe: Bool, expected: String) {
        #expect(LuckyDip.startVerb(kind: kind, site: site, isRecipe: recipe) == expected)
    }
}

/// A repeatable random number generator for tests.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct LuckyDipTests {
    let short = DipCandidate(id: UUID(), minutes: 8, timesSkipped: 0)
    let long = DipCandidate(id: UUID(), minutes: 45, timesSkipped: 0)
    let unknown = DipCandidate(id: UUID(), minutes: nil, timesSkipped: 0)

    @Test("It picks only blocks that fit the time limit")
    func timeLimit() {
        var random = Seeded(state: 1)
        for _ in 0..<50 {
            #expect(LuckyDip.pick(from: [short, long, unknown], maxMinutes: 10, using: &random) == short.id)
        }
        #expect(LuckyDip.pick(from: [long], maxMinutes: 10, using: &random) == nil)
        #expect(LuckyDip.fitting([short, long, unknown], maxMinutes: nil).count == 3)
    }

    @Test("Skipped blocks come up less often")
    func weighted() {
        let fresh = DipCandidate(id: UUID(), minutes: 5, timesSkipped: 0)
        let skipped = DipCandidate(id: UUID(), minutes: 5, timesSkipped: 4)
        var random = Seeded(state: 42)
        var counts: [UUID: Int] = [:]
        for _ in 0..<3000 {
            if let id = LuckyDip.pick(from: [fresh, skipped], maxMinutes: nil, using: &random) { counts[id, default: 0] += 1 }
        }
        // Weights 1 and 1/5: the fresh one should win about 5 times as often.
        let ratio = Double(counts[fresh.id] ?? 0) / Double(max(counts[skipped.id] ?? 0, 1))
        #expect(ratio > 3.5 && ratio < 7)
    }

    @Test("A re-spin never lands on the same block when there's another")
    func avoidsCurrent() {
        var random = Seeded(state: 7)
        for _ in 0..<50 {
            #expect(LuckyDip.pick(from: [short, long], maxMinutes: nil, avoiding: short.id, using: &random) == long.id)
        }
        #expect(LuckyDip.pick(from: [short], maxMinutes: nil, avoiding: short.id, using: &random) == short.id)
    }

    @Test("Two re-spins a day after the first spin")
    func spins() {
        #expect(LuckyDip.respinsLeft(spinsToday: 0) == 2 && LuckyDip.canSpin(spinsToday: 0))
        #expect(LuckyDip.respinsLeft(spinsToday: 1) == 2 && LuckyDip.canSpin(spinsToday: 1))
        #expect(LuckyDip.respinsLeft(spinsToday: 2) == 1)
        #expect(LuckyDip.respinsLeft(spinsToday: 3) == 0 && !LuckyDip.canSpin(spinsToday: 3))
    }

    @Test("The dip streak counts days in a row with a finished pick")
    func dipStreak() {
        #expect(LuckyDip.streak(finishedOn: [97, 98, 99, 100], today: 100) == 4)
        #expect(LuckyDip.streak(finishedOn: [97, 98, 99], today: 100) == 3)
        #expect(LuckyDip.streak(finishedOn: [96, 98, 99], today: 100) == 2)
        #expect(LuckyDip.streak(finishedOn: [97], today: 100) == 0)
    }

    @Test("Finished this week counts from Monday", arguments: [(1, 100), (3, 98), (7, 94)])
    func week(weekday: Int, start: Int) {
        #expect(LuckyDip.weekStart(today: 100, weekday: weekday) == start)
    }

    @Test("Total time of what Lucky Dip picks from")
    func total() {
        #expect(LuckyDip.totalTime([13, 47, nil, 130]) == "3 h 10 min")
        #expect(LuckyDip.totalTime([nil]) == "")
    }
}
