import Foundation

/// A folder from a browser's bookmarks export, with its links and subfolders (S-042).
public struct BookmarkFolder: Equatable, Sendable, Identifiable {
    public struct Link: Equatable, Sendable {
        public let url: URL
        public let title: String
        public let added: Date?
    }

    /// The folder's path from the top ("Bookmarks Bar/Recipes"), unique within one file.
    public let id: String
    public let name: String
    public var links: [Link] = []
    public var folders: [BookmarkFolder] = []

    /// Links here and in every folder inside.
    public var total: Int { links.count + folders.map(\.total).reduce(0, +) }

    /// Every folder inside, depth first, with its depth.
    public func flattened(depth: Int = 0) -> [(folder: BookmarkFolder, depth: Int)] {
        folders.flatMap { [($0, depth)] + $0.flattened(depth: depth + 1) }
    }
}

/// Reads the Netscape bookmark file format that Safari, Chrome, Firefox and Edge export:
/// `<DT><H3>Folder</H3><DL><p> … </DL><p>` for folders, `<DT><A HREF="…" ADD_DATE="…">Title</A>` for links.
public enum BookmarkFile {
    /// The file as a root folder: links outside any folder are the root's own links.
    public static func parse(_ html: String) -> BookmarkFolder {
        let pattern = #"(?is)<h3\b[^>]*>(.*?)</h3>|<a\b([^>]*)>(.*?)</a>|<dl\b[^>]*>|</dl>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return BookmarkFolder(id: "", name: "") }
        var stack = [BookmarkFolder(id: "", name: "")]
        var pendingFolder: String?
        var sawFirstList = false
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let token = html[range].lowercased()
            if let name = Range(match.range(at: 1), in: html) {
                pendingFolder = clean(String(html[name]))
            } else if let attributes = Range(match.range(at: 2), in: html), let title = Range(match.range(at: 3), in: html) {
                let attrs = String(html[attributes])
                guard let href = attribute("href", in: attrs), let url = URL(string: href),
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
                let added = attribute("add_date", in: attrs).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
                let name = clean(String(html[title]))
                stack[stack.count - 1].links.append(.init(url: url, title: name.isEmpty ? Links.siteName(url) : name, added: added))
            } else if token.hasPrefix("<dl") {
                if let name = pendingFolder {
                    let parentPath = stack.last?.id ?? ""
                    stack.append(BookmarkFolder(id: parentPath.isEmpty ? name : parentPath + "/" + name, name: name))
                    pendingFolder = nil
                } else if sawFirstList {
                    // A list without a heading: keep its links in the current folder.
                    stack.append(BookmarkFolder(id: (stack.last?.id ?? "") + "/…", name: ""))
                }
                sawFirstList = true
            } else if token.hasPrefix("</dl"), stack.count > 1 {
                let done = stack.removeLast()
                if done.name.isEmpty {
                    stack[stack.count - 1].links += done.links
                    stack[stack.count - 1].folders += done.folders
                } else {
                    stack[stack.count - 1].folders.append(done)
                }
            }
        }
        while stack.count > 1 {
            let done = stack.removeLast()
            stack[stack.count - 1].folders.append(done)
        }
        return stack[0]
    }

    /// What an import of the chosen folders would do: links to save (with the folder path they go
    /// into, nil for the Inbox) and how many are already saved, by normalized URL.
    public static func plan(_ root: BookmarkFolder, folders chosen: Set<String>, includeLoose: Bool,
                            existing: Set<String>) -> (items: [(link: BookmarkFolder.Link, folder: [String])], duplicates: Int) {
        var seen = existing
        var items: [(link: BookmarkFolder.Link, folder: [String])] = []
        var duplicates = 0
        func take(_ links: [BookmarkFolder.Link], into path: [String]) {
            for link in links {
                if seen.insert(Links.normalize(link.url)).inserted { items.append((link, path)) } else { duplicates += 1 }
            }
        }
        if includeLoose { take(root.links, into: []) }
        func walk(_ folder: BookmarkFolder, path: [String]) {
            let here = path + [folder.name]
            if chosen.contains(folder.id) { take(folder.links, into: here) }
            folder.folders.forEach { walk($0, path: here) }
        }
        root.folders.forEach { walk($0, path: []) }
        return (items, duplicates)
    }

    private static func attribute(_ name: String, in text: String) -> String? {
        let pattern = #"(?i)\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: text) { return decode(String(text[range])) }
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        Titles.clean(decode(text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)))
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
