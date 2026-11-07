import Foundation

/// What a page's HTML says about itself, beyond the title and picture LinkPresentation gives:
/// a video's length, a product's price, whether it's a recipe, and an article's length.
public struct PageFacts: Equatable, Sendable {
    public enum Kind: String, Sendable { case video, product, recipe, article }

    public var kind: Kind?
    public var durationSeconds: Int?
    public var price: Double?
    public var currency: String?
    public var wordCount: Int?
    /// The real title and author from oEmbed (YouTube's preview gives the channel name as the title).
    public var title: String?
    public var author: String?
    /// Where the page sent us with a meta refresh, when it did.
    public var redirectedTo: URL?

    public init(kind: Kind? = nil, durationSeconds: Int? = nil, price: Double? = nil, currency: String? = nil, wordCount: Int? = nil,
                title: String? = nil, author: String? = nil) {
        self.kind = kind
        self.title = title
        self.author = author
        self.durationSeconds = durationSeconds
        self.price = price
        self.currency = currency
        self.wordCount = wordCount
    }

    public var isRecipe: Bool { kind == .recipe }

    /// Watch time for a video, else read time for a page with enough text to be an article.
    public var minutes: Int? {
        if let durationSeconds, durationSeconds > 0 { return max(1, Int((Double(durationSeconds) / 60).rounded())) }
        if let wordCount { return PageReader.readMinutes(words: wordCount) }
        return nil
    }
}

/// Reads `PageFacts` from HTML: meta tags (og:, product:, itemprop) and schema.org JSON-LD.
public enum PageReader {
    /// Words per minute for read time.
    public static let wordsPerMinute = 230.0
    /// Fewer words than this isn't an article (a shop page, a login wall), so it gets no read time.
    public static let articleMinimumWords = 200

    public static func read(html: String) -> PageFacts {
        var facts = PageFacts()
        let meta = metaTags(html)
        let objects = jsonLD(html)

        // Video length: JSON-LD VideoObject, itemprop/og duration, or YouTube's player data.
        if let video = objects.first(where: { types($0).contains("VideoObject") }) {
            facts.kind = .video
            facts.durationSeconds = (video["duration"] as? String).flatMap(isoDuration)
        }
        if facts.durationSeconds == nil {
            facts.durationSeconds = meta["duration"].flatMap(isoDuration)
                ?? meta["video:duration"].flatMap { Int($0) }
                ?? meta["og:video:duration"].flatMap { Int($0) }
                ?? firstMatch(#""lengthSeconds"\s*:\s*"(\d+)""#, in: html).flatMap { Int($0) }
        }
        if meta["og:type"]?.hasPrefix("video") == true || facts.durationSeconds != nil { facts.kind = .video }

        // Price: JSON-LD Product with its offers, or product:/og: price meta tags.
        if facts.kind == nil {
            // Exactly one Product: a listing page with many isn't one product.
            let products = objects.filter { types($0).contains("Product") }
            if products.count == 1, let offer = price(in: products[0]["offers"]) {
                facts.kind = .product
                facts.price = offer.amount
                facts.currency = offer.currency
            } else if let amount = (meta["product:price:amount"] ?? meta["og:price:amount"]).flatMap(number) {
                facts.kind = .product
                facts.price = amount
                facts.currency = (meta["product:price:currency"] ?? meta["og:price:currency"])?.uppercased()
            }
        }

        // Recipe, then article read time.
        if facts.kind == nil, objects.contains(where: { types($0).contains("Recipe") }) {
            facts.kind = .recipe
        }
        if facts.kind == nil || facts.kind == .recipe {
            let declared = objects.lazy.compactMap { $0["wordCount"] }.compactMap { value -> Int? in
                (value as? Int) ?? (value as? String).flatMap { Int($0) }
            }.first
            let words = declared ?? wordCount(html: html)
            if words >= articleMinimumWords {
                facts.wordCount = words
                if facts.kind == nil { facts.kind = .article }
            }
        }
        return facts
    }

    /// Minutes to read this many words, at least 1.
    public static func readMinutes(words: Int) -> Int {
        max(1, Int((Double(words) / wordsPerMinute).rounded()))
    }

    /// Seconds in an ISO 8601 duration: "PT13M2S" → 782, "PT1H2M" → 3720, "P0DT0H5M" → 300.
    public static func isoDuration(_ text: String) -> Int? {
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func part(_ index: Int) -> Double {
            guard let range = Range(match.range(at: index), in: text) else { return 0 }
            return Double(text[range]) ?? 0
        }
        let seconds = part(1) * 86_400 + part(2) * 3600 + part(3) * 60 + part(4)
        return seconds > 0 ? Int(seconds.rounded()) : nil
    }

    /// Vimeo's oEmbed reply carries the video length in seconds.
    public static func oEmbedDuration(_ json: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        return (object["duration"] as? Int) ?? (object["duration"] as? Double).map { Int($0) }
    }

    /// An oEmbed reply's title and author ("But what is a neural network?", "3Blue1Brown").
    public static func oEmbedTitle(_ json: Data) -> (title: String, author: String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let title = object["title"] as? String, !title.isEmpty else { return nil }
        return (title, object["author_name"] as? String)
    }

    /// The address in `<meta http-equiv="refresh" content="0; url=…">`, resolved against the page.
    public static func metaRefresh(_ html: String, base: URL) -> URL? {
        guard let tag = firstMatch(#"(?is)(<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*>)"#, in: html),
              let target = firstMatch(#"(?i)url\s*=\s*['"]?([^'">\s]+)"#, in: tag) else { return nil }
        return URL(string: decodeEntities(target), relativeTo: base)?.absoluteURL
    }

    /// Words of readable text: inside <article> when the page has one, else <body>,
    /// without scripts, styles, navigation, headers and footers.
    public static func wordCount(html: String) -> Int {
        var text = firstMatch(#"(?is)<article\b[^>]*>(.*)</article>"#, in: html)
            ?? firstMatch(#"(?is)<body\b[^>]*>(.*)</body>"#, in: html) ?? html
        for tag in ["script", "style", "noscript", "svg", "nav", "header", "footer", "form", "template"] {
            text = text.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        return text.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: \.isLetter) }.count
    }

    // MARK: Pieces

    /// `<meta property|name|itemprop="…" content="…">`, keys lowercased, first one wins.
    static func metaTags(_ html: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let tag = try? NSRegularExpression(pattern: #"(?is)<meta\b[^>]*>"#),
              let attribute = try? NSRegularExpression(pattern: #"([a-zA-Z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else { return out }
        for match in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let text = String(html[range])
            var attributes: [String: String] = [:]
            for pair in attribute.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let name = Range(pair.range(at: 1), in: text) else { continue }
                let value = Range(pair.range(at: 2), in: text) ?? Range(pair.range(at: 3), in: text)
                attributes[text[name].lowercased()] = value.map { decodeEntities(String(text[$0])) } ?? ""
            }
            guard let content = attributes["content"],
                  let key = attributes["property"] ?? attributes["name"] ?? attributes["itemprop"] else { continue }
            if out[key.lowercased()] == nil { out[key.lowercased()] = content.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return out
    }

    /// Every object with an "@type" in the page's JSON-LD blocks, nested ones and @graph included.
    static func jsonLD(_ html: String) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<script\b[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#)
        else { return [] }
        var found: [[String: Any]] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["@type"] != nil { found.append(object) }
                object.values.forEach(walk)
            } else if let list = value as? [Any] {
                list.forEach(walk)
            }
        }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let data = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            walk(json)
        }
        return found
    }

    static func types(_ object: [String: Any]) -> [String] {
        let raw = object["@type"]
        let list = (raw as? [String]) ?? (raw as? String).map { [$0] } ?? []
        return list.map { $0.replacingOccurrences(of: "http://schema.org/", with: "").replacingOccurrences(of: "https://schema.org/", with: "") }
    }

    /// The price in an `offers` value: an Offer, an AggregateOffer (its lowPrice), or a list of them.
    static func price(in offers: Any?) -> (amount: Double, currency: String?)? {
        if let list = offers as? [Any] { return list.lazy.compactMap { price(in: $0) }.first }
        guard let offer = offers as? [String: Any] else { return nil }
        // priceSpecification can be one object or a list of them.
        let specs = (offer["priceSpecification"] as? [[String: Any]])
            ?? (offer["priceSpecification"] as? [String: Any]).map { [$0] } ?? []
        let spec = specs.first { number($0["price"]) != nil }
        let amount = number(offer["price"]) ?? number(offer["lowPrice"]) ?? spec.flatMap { number($0["price"]) }
        guard let amount else { return nil }
        let currency = (offer["priceCurrency"] as? String) ?? (spec?["priceCurrency"] as? String)
        return (amount, currency?.uppercased())
    }

    /// 189, "189.00", "1.299,00" or "1,299.00" as a number.
    static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        guard var text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        text = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        if let comma = text.lastIndex(of: ","), let dot = text.lastIndex(of: ".") {
            // The later one is the decimal mark.
            text = comma > dot ? text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                               : text.replacingOccurrences(of: ",", with: "")
        } else if let comma = text.lastIndex(of: ",") {
            // "189,00" is a decimal comma; "1,299" is a thousands comma.
            let after = text.distance(from: comma, to: text.endIndex) - 1
            text = after == 3 ? text.replacingOccurrences(of: ",", with: "") : text.replacingOccurrences(of: ",", with: ".")
        }
        return Double(text)
    }

    static func number(_ text: String) -> Double? { number(Optional<Any>.some(text)) }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}

/// Short labels for card badges.
public enum Badges {
    /// "13 min", "1 h 5 min", "2 h".
    public static func minutes(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(minutes, 1)) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "€189", "$59.90", "£1,299". Whole amounts drop the decimals.
    public static func price(_ amount: Double, currency: String?, locale: Locale = .current) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency ?? locale.currency?.identifier ?? "EUR", locale: locale)
            .precision(.fractionLength(amount.rounded() == amount ? 0 : 2))
        return amount.formatted(style)
    }
}
