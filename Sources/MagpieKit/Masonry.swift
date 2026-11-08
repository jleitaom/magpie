import Foundation

/// The Gallery's column layout: cards fill the shortest column first, so columns end at
/// about the same height and the order still reads left to right, top to bottom.
public enum Masonry {
    /// How many columns fit `width`, each at least `minColumn` wide, between 1 and `maxColumns`.
    public static func columnCount(width: Double, minColumn: Double, gap: Double, maxColumns: Int = 6) -> Int {
        guard width > 0, minColumn > 0 else { return 1 }
        let fits = Int((width + gap) / (minColumn + gap))
        return min(max(fits, 1), maxColumns)
    }

    /// The width of each column when `count` columns share `width`.
    public static func columnWidth(width: Double, count: Int, gap: Double) -> Double {
        let count = max(count, 1)
        return max((width - gap * Double(count - 1)) / Double(count), 0)
    }

    /// Which item indexes go in each column, given each item's estimated height.
    public static func columns(heights: [Double], count: Int, gap: Double) -> [[Int]] {
        let count = max(count, 1)
        var columns = Array(repeating: [Int](), count: count)
        var totals = Array(repeating: 0.0, count: count)
        for (index, height) in heights.enumerated() {
            // The shortest column; ties go to the leftmost, so the first row fills left to right.
            var target = 0
            for column in 1..<count where totals[column] < totals[target] { target = column }
            columns[target].append(index)
            totals[target] += height + gap
        }
        return columns
    }
}

/// How many collections fit in the top bar.
public enum Pins {
    public static let limit = 5

    public static func canPin(currentlyPinned: Int) -> Bool { currentlyPinned < limit }
}

/// Arrow keys in the masonry (S-032): up and down within a column, left and right to the card
/// in the next column whose top is closest.
public enum GridNavigation {
    public enum Direction: Sendable { case up, down, left, right }

    /// `columns` holds item indexes per column, top to bottom; `heights` each item's height.
    public static func next(from item: Int, _ direction: Direction, columns: [[Int]], heights: [Double], gap: Double) -> Int? {
        var tops: [Int: Double] = [:]
        for column in columns {
            var y = 0.0
            for index in column {
                tops[index] = y
                y += heights[index] + gap
            }
        }
        guard let column = columns.firstIndex(where: { $0.contains(item) }),
              let row = columns[column].firstIndex(of: item), let top = tops[item] else { return nil }
        switch direction {
        case .up: return row > 0 ? columns[column][row - 1] : nil
        case .down: return row + 1 < columns[column].count ? columns[column][row + 1] : nil
        case .left, .right:
            let target = column + (direction == .left ? -1 : 1)
            guard columns.indices.contains(target), !columns[target].isEmpty else { return nil }
            return columns[target].min { abs((tops[$0] ?? 0) - top) < abs((tops[$1] ?? 0) - top) }
        }
    }
}
