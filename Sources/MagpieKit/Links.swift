import Foundation

/// What a saved link points to, guessed from the URL before any download.
public enum LinkKind: String, Sendable, CaseIterable {
    case link, video, place, image
}

/// Rules for links: reading what the user pasted, spotting duplicates, and naming sites.
public enum Links {
    /// Query parameters that only track where a click came from. Removed when comparing links.
    static let trackingNames: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid",
                                             "igshid", "igsh", "si", "ref_src", "ref_url", "_hsenc", "_hsmi"]

    /// A web link from pasted or dropped text, or nil when the text isn't one.
    /// Accepts "https://…", "http://…", and bare "example.com/path".
    public static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        return url
    }

    /// Web links and files, the only addresses a block opens.
    public static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }

    /// The same string for links that point to the same page: lowercased host without "www.",
    /// no tracking parameters, no fragment, no trailing slash, and http treated as https.
    public static func normalize(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.scheme = "https"
        if let host = parts.host?.lowercased() {
            parts.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        parts.fragment = nil
        if let items = parts.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingNames.contains(name)
            }
            parts.queryItems = kept.isEmpty ? nil : kept.sorted { $0.name < $1.name }
        }
        var path = parts.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        parts.path = path == "/" ? "" : path
        return parts.string ?? url.absoluteString
    }

    /// "youtube.com" for "https://www.youtube.com/watch?v=…".
    public static func siteName(_ url: URL) -> String {
        guard let host = url.host()?.lowercased() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func kind(_ url: URL) -> LinkKind {
        let host = siteName(url)
        let path = url.path.lowercased()
        let imageTypes = ["jpg", "jpeg", "png", "gif", "webp", "heic", "avif"]
        if imageTypes.contains(url.pathExtension.lowercased()) { return .image }
        if host == "youtu.be" || host.hasSuffix("youtube.com") || host == "vimeo.com" || host.hasSuffix(".vimeo.com")
            || host.hasSuffix("tiktok.com") { return .video }
        if host == "maps.apple.com" || host == "maps.app.goo.gl" || (host == "goo.gl" && path.hasPrefix("/maps"))
            || (host.hasPrefix("maps.google.")) || (host.hasSuffix("google.com") && path.hasPrefix("/maps")) { return .place }
        return .link
    }
}

extension Links {
    /// A place's name from its maps link: "Torre de Belém" from
    /// google.com/maps/place/Torre+de+Bel%C3%A9m or maps.apple.com/?q=Torre+de+Belem.
    public static func placeName(_ url: URL) -> String? {
        guard kind(url) == .place else { return nil }
        let parts = url.pathComponents
        if let index = parts.firstIndex(of: "place"), parts.indices.contains(index + 1) {
            return clean(parts[index + 1])
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for key in ["name", "q", "address", "daddr", "query"] {
            if let value = items.first(where: { $0.name == key })?.value, !value.isEmpty { return clean(value) }
        }
        return nil
    }

    private static func clean(_ text: String) -> String? {
        let decoded = (text.removingPercentEncoding ?? text).replacingOccurrences(of: "+", with: " ")
        let trimmed = Titles.clean(decoded)
        // Coordinates aren't a name.
        if trimmed.isEmpty || trimmed.allSatisfy({ $0.isNumber || ".,- ".contains($0) }) { return nil }
        return trimmed
    }
}

/// A saved block's title from page text: whitespace collapsed, trimmed, and kept to one line.
public enum Titles {
    public static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first non-empty line of a note, for its title.
    public static func firstLine(_ text: String, limit: Int = 80) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = clean(line)
        return cleaned.count > limit ? String(cleaned.prefix(limit - 1)) + "…" : cleaned
    }
}
