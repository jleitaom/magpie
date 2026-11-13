import Foundation

/// Nesting and order rules for collections, with no SwiftData, so they can be unit tested.
/// The app turns its collections into `TreeNode`s, asks here what to do, and writes the answer back.
public struct TreeNode: Equatable, Sendable {
    public let id: UUID
    public let parent: UUID?
    public let sortIndex: Double

    public init(id: UUID, parent: UUID?, sortIndex: Double) {
        self.id = id
        self.parent = parent
        self.sortIndex = sortIndex
    }
}

/// Where a dragged collection goes, relative to the row it was dropped on.
public enum TreePlacement: Equatable, Sendable {
    case before(UUID)
    case after(UUID)
    case inside(UUID)
    /// The end of the top level.
    case topLevel
}

public enum CollectionTree {
    /// Display order: each parent followed by its children, indented one step per level.
    /// A node whose parent is missing counts as top level, so nothing ever disappears.
    public static func flatten(_ nodes: [TreeNode]) -> [(id: UUID, depth: Int)] {
        let ids = Set(nodes.map(\.id))
        var children: [UUID?: [TreeNode]] = [:]
        for node in nodes {
            let parent = node.parent.flatMap { ids.contains($0) && $0 != node.id ? $0 : nil }
            children[parent, default: []].append(node)
        }
        var out: [(id: UUID, depth: Int)] = []
        var seen: Set<UUID> = []
        func walk(_ parent: UUID?, _ depth: Int) {
            for node in sorted(children[parent] ?? []) where seen.insert(node.id).inserted {
                out.append((node.id, depth))
                walk(node.id, depth + 1)
            }
        }
        walk(nil, 0)
        // A loop in the data (a parent of its own parent) would hide nodes. Show them at the top level.
        for node in sorted(nodes) where !seen.contains(node.id) {
            seen.insert(node.id)
            out.append((node.id, 0))
        }
        return out
    }

    /// True when `id` sits somewhere under `ancestor`.
    public static func isDescendant(_ id: UUID, of ancestor: UUID, in nodes: [TreeNode]) -> Bool {
        let parents = Dictionary(nodes.map { ($0.id, $0.parent) }, uniquingKeysWith: { first, _ in first })
        var current = parents[id] ?? nil
        var steps = 0
        while let step = current, steps <= nodes.count {
            if step == ancestor { return true }
            current = parents[step] ?? nil
            steps += 1
        }
        return false
    }

    /// A collection can go inside any other collection except itself and its own children.
    public static func canNest(_ id: UUID, under parent: UUID?, in nodes: [TreeNode]) -> Bool {
        guard let parent else { return true }
        return parent != id && !isDescendant(parent, of: id, in: nodes)
    }

    /// The new parent and sortIndex for `id` dropped at `placement`, or nil when the move isn't allowed.
    public static func move(_ id: UUID, to placement: TreePlacement, in nodes: [TreeNode]) -> (parent: UUID?, sortIndex: Double)? {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func siblings(of parent: UUID?) -> [TreeNode] {
            sorted(nodes.filter { $0.parent == parent && $0.id != id })
        }
        switch placement {
        case .topLevel:
            return (nil, (siblings(of: nil).last?.sortIndex ?? 0) + 1)
        case .inside(let target):
            guard byID[target] != nil, canNest(id, under: target, in: nodes) else { return nil }
            return (target, (siblings(of: target).last?.sortIndex ?? 0) + 1)
        case .before(let target), .after(let target):
            guard target != id, let anchor = byID[target], canNest(id, under: anchor.parent, in: nodes) else { return nil }
            let row = siblings(of: anchor.parent)
            guard let index = row.firstIndex(where: { $0.id == target }) else { return nil }
            if case .before = placement {
                let previous = index > 0 ? row[index - 1].sortIndex : anchor.sortIndex - 2
                return (anchor.parent, (previous + anchor.sortIndex) / 2)
            } else {
                let next = index + 1 < row.count ? row[index + 1].sortIndex : anchor.sortIndex + 2
                return (anchor.parent, (anchor.sortIndex + next) / 2)
            }
        }
    }

    /// Move Up or Move Down among the collections that share its parent. Nil at either end.
    public static func step(_ id: UUID, up: Bool, in nodes: [TreeNode]) -> (parent: UUID?, sortIndex: Double)? {
        guard let node = nodes.first(where: { $0.id == id }) else { return nil }
        let row = sorted(nodes.filter { $0.parent == node.parent })
        guard let index = row.firstIndex(where: { $0.id == id }) else { return nil }
        let target = up ? index - 1 : index + 1
        guard row.indices.contains(target) else { return nil }
        return move(id, to: up ? .before(row[target].id) : .after(row[target].id), in: nodes)
    }

    /// The text of the delete confirmation. Nothing but the collection itself is deleted.
    public static func deleteMessage(blockCount: Int, childCount: Int) -> String {
        var parts: [String] = []
        switch blockCount {
        case 0: parts.append("It has no blocks.")
        case 1: parts.append("Its block goes back to the Inbox.")
        default: parts.append("Its \(blockCount) blocks go back to the Inbox.")
        }
        switch childCount {
        case 0: break
        case 1: parts.append("The pile inside it moves up a level.")
        default: parts.append("The \(childCount) piles inside it move up a level.")
        }
        parts.append("No blocks are deleted.")
        return parts.joined(separator: " ")
    }

    private static func sorted(_ nodes: [TreeNode]) -> [TreeNode] {
        nodes.sorted { $0.sortIndex == $1.sortIndex ? $0.id.uuidString < $1.id.uuidString : $0.sortIndex < $1.sortIndex }
    }
}
