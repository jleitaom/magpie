import Foundation

/// Search (S-031): ignores case and accents, and matches the start of words.
/// "cafe lis" finds "Café in Lisbon": every word typed must start some word in the block.
public enum Search {
    /// Lowercased, accents removed, so "Café" and "cafe" compare equal.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// The words of a text, folded. Letters and digits only; anything else separates words.
    public static func words(_ text: String) -> [Substring] {
        fold(text).split { !$0.isLetter && !$0.isNumber }
    }

    /// The words typed, folded.
    public static func terms(_ query: String) -> [String] {
        words(query).map(String.init)
    }

    /// A block's searchable text, folded once so typing stays fast: its words, one per line.
    public static func index(_ fields: [String?]) -> String {
        fields.compactMap { $0 }.flatMap(words).joined(separator: "\n")
    }

    /// True when every term starts some word in the index. An empty query matches nothing.
    public static func matches(index: String, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        return terms.allSatisfy { term in
            index.hasPrefix(term) || index.contains("\n" + term)
        }
    }

    /// Where the terms appear at the start of a word in `text`, for highlighting.
    public static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
        guard !terms.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            // The start of a word: a letter or digit after a non-letter (or at the start).
            let isStart = (text[index].isLetter || text[index].isNumber)
                && (index == text.startIndex || !(text[text.index(before: index)].isLetter || text[text.index(before: index)].isNumber))
            if isStart {
                for term in terms {
                    if let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .anchored],
                                              range: index..<text.endIndex) {
                        found.append(range)
                        break
                    }
                }
            }
            index = text.index(after: index)
        }
        return found
    }
}

/// Totals for a collection's strip (S-073, S-074).
public enum Totals {
    /// "€442 + $60": one total per currency, largest first. Blocks with no currency count in `fallback`.
    public static func money(_ prices: [(amount: Double, currency: String?)], fallback: String, locale: Locale = .current) -> String {
        var sums: [String: Double] = [:]
        for price in prices { sums[price.currency ?? fallback, default: 0] += price.amount }
        return sums.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { Badges.price($0.value, currency: $0.key, locale: locale) }
            .joined(separator: " + ")
    }
}
