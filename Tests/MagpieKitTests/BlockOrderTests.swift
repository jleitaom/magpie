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

struct ManualOrderTests {
    @Test("Inserting between two blocks uses the midpoint, with no renumbering")
    func midpoint() {
        #expect(ManualOrder.index(between: 1, and: 2) == 1.5)
        #expect(ManualOrder.index(between: 3, and: nil) == 4)
        #expect(ManualOrder.index(between: nil, and: 1) == 0)
        #expect(ManualOrder.numbered(3) == [1, 2, 3])
    }

    @Test("A dropped block takes the target's place")
    func drop() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let ids = [a, b, c, d]
        let indexes: [UUID: Double] = [a: 1, b: 2, c: 3, d: 4]
        #expect(ManualOrder.drop(d, onto: b, in: ids, indexes: indexes) == 1.5)   // d moves up, before b
        #expect(ManualOrder.drop(a, onto: c, in: ids, indexes: indexes) == 3.5)   // a moves down, after c
        #expect(ManualOrder.drop(a, onto: d, in: ids, indexes: indexes) == 5)     // to the end
        #expect(ManualOrder.drop(a, onto: a, in: ids, indexes: indexes) == nil)
    }

    @Test("Manual lists blocks by their sortIndex")
    func manual() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = OrderItem(id: UUID(), createdAt: now, minutes: nil, title: "a", site: "", color: nil, sortIndex: 2)
        let b = OrderItem(id: UUID(), createdAt: now, minutes: nil, title: "b", site: "", color: nil, sortIndex: 1.5)
        #expect(BlockOrder.manual.sorted([a, b]) == [b.id, a.id])
    }
}

struct GridNavigationTests {
    // Two columns: [0 (h 100), 2 (h 100)] and [1 (h 220), 3 (h 50)].
    let columns = [[0, 2], [1, 3]]
    let heights: [Double] = [100, 220, 100, 50]

    @Test("Up and down stay in the column")
    func vertical() {
        #expect(GridNavigation.next(from: 0, .down, columns: columns, heights: heights, gap: 16) == 2)
        #expect(GridNavigation.next(from: 2, .up, columns: columns, heights: heights, gap: 16) == 0)
        #expect(GridNavigation.next(from: 2, .down, columns: columns, heights: heights, gap: 16) == nil)
    }

    @Test("Left and right go to the nearest card in the next column")
    func horizontal() {
        #expect(GridNavigation.next(from: 0, .right, columns: columns, heights: heights, gap: 16) == 1)
        // Item 2's top is 116; item 1's top is 0 and item 3's is 236: 1 is closer.
        #expect(GridNavigation.next(from: 2, .right, columns: columns, heights: heights, gap: 16) == 1)
        #expect(GridNavigation.next(from: 3, .left, columns: columns, heights: heights, gap: 16) == 2)
        #expect(GridNavigation.next(from: 0, .left, columns: columns, heights: heights, gap: 16) == nil)
    }
}

struct DetailsColumnTests {
    @Test("The details header names what the blocks have, and only lengths sort")
    func header() {
        #expect(DetailsColumn(hasLength: true, hasPrice: false) == .length)
        #expect(DetailsColumn(hasLength: false, hasPrice: true) == .price)
        #expect(DetailsColumn(hasLength: true, hasPrice: true) == .details)
        #expect(DetailsColumn(hasLength: false, hasPrice: false) == .details)
        #expect(DetailsColumn.length.sortsByLength)
        #expect(!DetailsColumn.price.sortsByLength && !DetailsColumn.details.sortsByLength)
    }
}
