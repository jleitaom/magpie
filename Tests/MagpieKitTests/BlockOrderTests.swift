import Foundation
import Testing
@testable import MagpieKit

struct BlockOrderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ title: String, ago hours: Double, minutes: Int? = nil, site: String = "a.com", color: UInt32? = nil) -> OrderItem {
        OrderItem(id: UUID(), createdAt: now.addingTimeInterval(-hours * 3600), minutes: minutes, title: title, site: site, color: color)
    }

    @Test("Newest and oldest")
    func byDate() {
        let a = item("a", ago: 1), b = item("b", ago: 5), c = item("c", ago: 3)
        #expect(BlockOrder.newest.sorted([a, b, c]) == [a.id, c.id, b.id])
        #expect(BlockOrder.oldest.sorted([a, b, c]) == [b.id, c.id, a.id])
    }

    @Test("Quickest puts blocks with no known length last")
    func quickest() {
        let long = item("long", ago: 1, minutes: 45), none = item("none", ago: 2), short = item("short", ago: 3, minutes: 5), none2 = item("none2", ago: 4)
        #expect(BlockOrder.quickest.sorted([long, none, short, none2]) == [short.id, long.id, none.id, none2.id])
    }

    @Test("Title A–Z reads numbers naturally and ignores case")
    func title() {
        let b = item("blue Train", ago: 1), a = item("A Love Supreme", ago: 2), k10 = item("Kind 10", ago: 3), k9 = item("Kind 9", ago: 4)
        #expect(BlockOrder.title.sorted([b, k10, a, k9]) == [a.id, b.id, k9.id, k10.id])
    }

    @Test("Site groups blocks from the same place")
    func site() {
        let y1 = item("y1", ago: 1, site: "youtube.com"), d = item("d", ago: 2, site: "discogs.com"), y2 = item("y2", ago: 3, site: "youtube.com")
        #expect(BlockOrder.site.sorted([y1, d, y2]) == [d.id, y1.id, y2.id])
    }

    @Test("Color sorts by hue, with greys last")
    func color() {
        let blue = item("blue", ago: 1, color: 0x2C5D8A), grey = item("grey", ago: 2, color: 0x808080), red = item("red", ago: 3, color: 0xC8553D)
        let none = item("none", ago: 4), green = item("green", ago: 5, color: 0x7A8F6A)
        #expect(BlockOrder.color.sorted([blue, grey, red, none, green]) == [red.id, green.id, blue.id, grey.id, none.id])
    }

    @Test("Shuffle: the same seed gives the same order, a new seed a new one")
    func shuffle() {
        let items = (0..<12).map { item("\($0)", ago: Double($0)) }
        let first = BlockOrder.shuffle.sorted(items, seed: 1)
        #expect(BlockOrder.shuffle.sorted(items, seed: 1) == first)
        #expect(BlockOrder.shuffle.sorted(items, seed: 2) != first)
        #expect(Set(first) == Set(items.map(\.id)))
        #expect(first != BlockOrder.newest.sorted(items))
    }
}
