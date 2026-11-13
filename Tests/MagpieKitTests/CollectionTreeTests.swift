import Foundation
import Testing
@testable import MagpieKit

struct CollectionTreeTests {
    // Reading (1) ─ Articles (2) ─ Long reads (3)
    // Shopping (4)
    // Ideas (5)
    let reading = UUID(), articles = UUID(), longReads = UUID(), shopping = UUID(), ideas = UUID()
    var nodes: [TreeNode] {
        [
            TreeNode(id: shopping, parent: nil, sortIndex: 2),
            TreeNode(id: longReads, parent: articles, sortIndex: 1),
            TreeNode(id: reading, parent: nil, sortIndex: 1),
            TreeNode(id: ideas, parent: nil, sortIndex: 3),
            TreeNode(id: articles, parent: reading, sortIndex: 1),
        ]
    }

    @Test("Children follow their parent, one level deeper")
    func flatten() {
        let rows = CollectionTree.flatten(nodes)
        #expect(rows.map(\.id) == [reading, articles, longReads, shopping, ideas])
        #expect(rows.map(\.depth) == [0, 1, 2, 0, 0])
    }

    @Test("A pile whose parent is gone shows at the top level")
    func orphan() {
        let lost = UUID()
        let rows = CollectionTree.flatten(nodes + [TreeNode(id: lost, parent: UUID(), sortIndex: 9)])
        #expect(rows.last?.id == lost && rows.last?.depth == 0)
    }

    @Test("A loop in the data never hides a pile")
    func loop() {
        let a = UUID(), b = UUID()
        let rows = CollectionTree.flatten([TreeNode(id: a, parent: b, sortIndex: 1), TreeNode(id: b, parent: a, sortIndex: 2)])
        #expect(Set(rows.map(\.id)) == [a, b])
    }

    @Test("A pile can't be nested inside itself or its own child")
    func noNestingInsideOwnChild() {
        #expect(!CollectionTree.canNest(reading, under: reading, in: nodes))
        #expect(!CollectionTree.canNest(reading, under: articles, in: nodes))
        #expect(!CollectionTree.canNest(reading, under: longReads, in: nodes))
        #expect(CollectionTree.move(reading, to: .inside(longReads), in: nodes) == nil)
        #expect(CollectionTree.move(reading, to: .before(longReads), in: nodes) == nil)
        #expect(CollectionTree.canNest(longReads, under: shopping, in: nodes))
        #expect(CollectionTree.canNest(articles, under: nil, in: nodes))
    }

    @Test("Dropping inside makes it the last child")
    func inside() throws {
        let result = try #require(CollectionTree.move(ideas, to: .inside(reading), in: nodes))
        #expect(result.parent == reading && result.sortIndex == 2)
    }

    @Test("Dropping before or after lands between its new neighbors")
    func beforeAfter() throws {
        let before = try #require(CollectionTree.move(ideas, to: .before(shopping), in: nodes))
        #expect(before.parent == nil && before.sortIndex > 1 && before.sortIndex < 2)
        let after = try #require(CollectionTree.move(reading, to: .after(shopping), in: nodes))
        #expect(after.parent == nil && after.sortIndex > 2 && after.sortIndex < 3)
        let first = try #require(CollectionTree.move(ideas, to: .before(reading), in: nodes))
        #expect(first.sortIndex < 1)
        let nested = try #require(CollectionTree.move(shopping, to: .after(longReads), in: nodes))
        #expect(nested.parent == articles && nested.sortIndex > 1)
    }

    @Test("Move Up and Move Down swap with a neighbor and stop at the ends")
    func step() throws {
        let up = try #require(CollectionTree.step(shopping, up: true, in: nodes))
        #expect(up.parent == nil && up.sortIndex < 1)
        let down = try #require(CollectionTree.step(shopping, up: false, in: nodes))
        #expect(down.sortIndex > 3)
        #expect(CollectionTree.step(reading, up: true, in: nodes) == nil)
        #expect(CollectionTree.step(ideas, up: false, in: nodes) == nil)
        #expect(CollectionTree.step(longReads, up: true, in: nodes) == nil)
    }

    @Test("The delete confirmation says where the blocks go, with the count", arguments: [
        (0, 0, "It has no blocks. No blocks are deleted."),
        (1, 0, "Its block goes back to the Inbox. No blocks are deleted."),
        (12, 0, "Its 12 blocks go back to the Inbox. No blocks are deleted."),
        (3, 1, "Its 3 blocks go back to the Inbox. The pile inside it moves up a level. No blocks are deleted."),
        (3, 2, "Its 3 blocks go back to the Inbox. The 2 piles inside it move up a level. No blocks are deleted."),
    ])
    func deleteMessage(blocks: Int, children: Int, text: String) {
        #expect(CollectionTree.deleteMessage(blockCount: blocks, childCount: children) == text)
    }
}
