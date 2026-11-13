import Foundation
import Testing
@testable import MagpieKit

struct RediscoverTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    func candidate(saved: Double, opened: Double? = nil, shown: Double? = nil, skips: Int = 0) -> RediscoverCandidate {
        RediscoverCandidate(id: UUID(), createdAt: daysAgo(saved), openedAt: opened.map(daysAgo), lastShownAt: shown.map(daysAgo), timesSkipped: skips)
    }

    @Test("Only blocks not opened in 14+ days come up")
    func eligibility() {
        #expect(Rediscover.isEligible(candidate(saved: 30), now: now))
        #expect(!Rediscover.isEligible(candidate(saved: 3), now: now))
        #expect(!Rediscover.isEligible(candidate(saved: 60, opened: 2), now: now))
        #expect(Rediscover.isEligible(candidate(saved: 60, opened: 20), now: now))
        #expect(!Rediscover.isEligible(candidate(saved: 60, shown: 5), now: now))
    }

    @Test("It picks 5, never twice the same")
    func five() {
        var random = Seeded(state: 3)
        let pool = (0..<12).map { _ in candidate(saved: 40) } + [candidate(saved: 1)]
        let picked = Rediscover.pick(from: pool, now: now, using: &random)
        #expect(picked.count == 5 && Set(picked).count == 5)
        #expect(!picked.contains(pool.last!.id))
        #expect(Rediscover.pick(from: [candidate(saved: 40)], now: now, using: &random).count == 1)
    }

    @Test("Blocks skipped less often come up more")
    func weighted() {
        let fresh = candidate(saved: 40), skipped = candidate(saved: 40, skips: 5)
        var random = Seeded(state: 11)
        var freshFirst = 0
        for _ in 0..<1000 where Rediscover.pick(from: [skipped, fresh], now: now, count: 1, using: &random).first == fresh.id {
            freshFirst += 1
        }
        #expect(freshFirst > 750)
    }
}

struct DockDropTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A quick drop steps back; waiting on the icon or using Magpie keeps it in front")
    func stepBack() {
        #expect(DockDrop.shouldStepBack(activeSince: now.addingTimeInterval(-0.2), wasRunning: true, now: now))
        #expect(!DockDrop.shouldStepBack(activeSince: now.addingTimeInterval(-2.5), wasRunning: true, now: now))
        #expect(!DockDrop.shouldStepBack(activeSince: now.addingTimeInterval(-600), wasRunning: true, now: now))
        #expect(DockDrop.shouldStepBack(activeSince: nil, wasRunning: true, now: now))
    }

    @Test("A drop that launches Magpie saves and steps back")
    func launched() {
        #expect(DockDrop.shouldStepBack(activeSince: now, wasRunning: false, now: now))
    }
}

struct DropHintTests {
    @Test("The drop hint shows only while the library is new", arguments: [(0, false), (1, true), (4, true), (5, false), (500, false)])
    func shows(count: Int, expected: Bool) {
        #expect(DropHint.shows(blockCount: count) == expected)
    }
}
