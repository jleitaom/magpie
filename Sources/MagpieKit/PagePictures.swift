import Foundation

/// The pictures a page offers, to choose a block's picture from (#2).
public enum PagePictures {
    /// At most this many candidates, best first.
    public static let limit = 16

    /// Picture addresses in the page, best first, without duplicates: the share pictures
    /// (`og:image`, `twitter:image`, `image_src`), the page's structured data (JSON-LD `image`),
    /// then the `<img>` tags that look like content (not icons, logos, avatars, tracking pixels
    /// or SVG). Only web addresses: a page can never make Magpie read a local file.
    public static func candidates(html: String, base: URL) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        func add(_ text: String?) {
            guard found.count < limit, let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let url = URL(string: PageReader.decodeEntities(text), relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  !looksLikeChrome(url) else { return }
            if seen.insert(url.absoluteString).inserted { found.append(url) }
        }
        // Share pictures: every og:image (pages often list several), then the others.
        for tag in tags("meta", in: html) {
            let key = (tag["property"] ?? tag["name"] ?? tag["itemprop"])?.lowercased()
            if ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src", "image"].contains(key ?? "") {
                add(tag["content"])
            }
        }
        for tag in tags("link", in: html) where tag["rel"]?.lowercased() == "image_src" { add(tag["href"]) }
        // Structured data: a product's or article's "image", which can be a string, a list or an ImageObject.
        for object in PageReader.jsonLD(html) {
            for text in imageStrings(object["image"]) { add(text) }
        }
        // Content images: the largest candidate in srcset, else src (or a lazy-loading data-src).
        for tag in tags("img", in: html) {
            if let width = tag["width"].flatMap(Int.init), width < minimumSide { continue }
            if let height = tag["height"].flatMap(Int.init), height < minimumSide { continue }
            add(largest(inSrcset: tag["srcset"] ?? tag["data-srcset"]) ?? tag["data-src"] ?? tag["src"])
        }
        return found
    }

    /// Smaller than this (in the page's own width or height) is an icon, not a picture.
    public static let minimumSide = 150

    /// Icons, logos, avatars, sprites, tracking pixels and vector art: never a block's picture.
    static func looksLikeChrome(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.hasSuffix(".svg") || path.hasSuffix(".ico") || path.hasSuffix(".gif") { return true }
        let words = ["logo", "icon", "favicon", "avatar", "sprite", "pixel", "spacer", "badge", "emoji", "placeholder"]
        let name = url.lastPathComponent.lowercased()
        return words.contains { name.contains($0) } || path.contains("/icons/") || path.contains("/avatars/")
    }

    /// The URL with the biggest width (or density) in a srcset.
    static func largest(inSrcset srcset: String?) -> String? {
        guard let srcset, !srcset.isEmpty else { return nil }
        let entries: [(url: String, size: Double)] = srcset.split(separator: ",").compactMap { part in
            let bits = part.split(whereSeparator: \.isWhitespace)
            guard let url = bits.first else { return nil }
            let size = bits.dropFirst().first.flatMap { Double($0.dropLast()) } ?? 1
            return (String(url), size)
        }
        return entries.max { $0.size < $1.size }?.url
    }

    private static func imageStrings(_ value: Any?) -> [String] {
        if let text = value as? String { return [text] }
        if let list = value as? [Any] { return list.flatMap(imageStrings) }
        if let object = value as? [String: Any] { return imageStrings(object["url"] ?? object["contentUrl"]) }
        return []
    }

    /// Every `<name …>` tag's attributes, names lowercased.
    static func tags(_ name: String, in html: String) -> [[String: String]] {
        guard let tag = try? NSRegularExpression(pattern: "(?is)<\(name)\\b[^>]*>"),
              let attribute = try? NSRegularExpression(pattern: #"([a-zA-Z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#) else { return [] }
        return tag.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            let text = String(html[range])
            var attributes: [String: String] = [:]
            for pair in attribute.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let key = Range(pair.range(at: 1), in: text) else { continue }
                let value = (2...4).lazy.compactMap { Range(pair.range(at: $0), in: text) }.first
                attributes[text[key].lowercased()] = value.map { String(text[$0]) } ?? ""
            }
            return attributes
        }
    }
}
