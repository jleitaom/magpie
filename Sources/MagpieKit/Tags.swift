import Foundation

/// Tag names: cleaning what was typed, telling which names are the same tag, and suggesting
/// existing tags while you type.
public enum Tags {
    /// What was typed, tidied: no leading "#", spaces collapsed, trimmed.
    public static func clean(_ text: String) -> String {
        var trimmed = Titles.clean(text)
        while trimmed.hasPrefix("#") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return trimmed
    }

    /// The same key for names that are the same tag. Case doesn't matter: "Jazz" and "jazz" are one tag.
    public static func key(_ name: String) -> String {
        clean(name).lowercased()
    }

    /// Several tags typed at once, separated by commas: "jazz, vinyl, Jazz" → ["jazz", "vinyl"].
    public static func parse(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text.split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }

    /// Existing tags that match what's typed: names starting with it first, then names containing it.
    /// Tags the block already has are left out.
    public static func suggestions(for text: String, from names: [String], excluding: [String] = [], limit: Int = 6) -> [String] {
        let query = key(text)
        let taken = Set(excluding.map(key))
        let pool = names.filter { !taken.contains(key($0)) }
        guard !query.isEmpty else { return Array(pool.sorted { key($0) < key($1) }.prefix(limit)) }
        let starts = pool.filter { key($0).hasPrefix(query) }.sorted { key($0) < key($1) }
        let contains = pool.filter { !key($0).hasPrefix(query) && key($0).contains(query) }.sorted { key($0) < key($1) }
        return Array((starts + contains).prefix(limit))
    }
}
