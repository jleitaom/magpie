import Foundation
import Testing
@testable import MagpieKit

struct PageReaderTests {
    @Test("ISO 8601 durations", arguments: [
        ("PT13M2S", 782), ("PT1H2M", 3720), ("PT45S", 45), ("P0DT0H5M", 300), ("PT1H0M0S", 3600),
    ])
    func iso(text: String, seconds: Int) {
        #expect(PageReader.isoDuration(text) == seconds)
    }

    @Test("Bad durations read as none", arguments: ["", "13:02", "PT", "P1Y"])
    func badIso(text: String) {
        #expect(PageReader.isoDuration(text) == nil)
    }

    @Test("A video's length comes from its page metadata")
    func videoMeta() {
        let youtube = #"<html><head><meta itemprop="duration" content="PT13M2S"><meta property="og:type" content="video.other"></head></html>"#
        let facts = PageReader.read(html: youtube)
        #expect(facts.kind == .video && facts.durationSeconds == 782 && facts.minutes == 13)

        let player = #"<script>var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":"1105","title":"x"}};</script>"#
        #expect(PageReader.read(html: player).minutes == 18)

        let ld = #"<script type="application/ld+json">{"@context":"https://schema.org","@type":"VideoObject","name":"A","duration":"PT4M"}</script>"#
        #expect(PageReader.read(html: ld).durationSeconds == 240)
    }

    @Test("Vimeo's oEmbed gives the duration")
    func oEmbed() {
        #expect(PageReader.oEmbedDuration(Data(#"{"type":"video","duration":634,"title":"T"}"#.utf8)) == 634)
        #expect(PageReader.oEmbedDuration(Data("{}".utf8)) == nil)
    }

    @Test("A price comes from schema.org Product and Offer")
    func productLD() {
        let html = #"""
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":"Product","name":"Lamp",
         "offers":{"@type":"Offer","price":"189.00","priceCurrency":"eur"}}]}
        </script>
        """#
        let facts = PageReader.read(html: html)
        #expect(facts.kind == .product && facts.price == 189 && facts.currency == "EUR")
    }

    @Test("Offer lists and AggregateOffer's lowPrice work too")
    func offers() {
        let list = #"<script type="application/ld+json">{"@type":"Product","offers":[{"@type":"Offer","price":59.9,"priceCurrency":"USD"}]}</script>"#
        #expect(PageReader.read(html: list).price == 59.9)
        let aggregate = #"<script type="application/ld+json">{"@type":["Product"],"offers":{"@type":"AggregateOffer","lowPrice":"1.299,00","priceCurrency":"EUR"}}</script>"#
        #expect(PageReader.read(html: aggregate).price == 1299)
    }

    @Test("A price inside a list of priceSpecification works")
    func priceSpecification() {
        let html = #"<script type="application/ld+json">{"@type":"Product","offers":{"@type":"Offer","priceSpecification":[{"@type":"UnitPriceSpecification","price":79,"priceCurrency":"USD"}]}}</script>"#
        let facts = PageReader.read(html: html)
        #expect(facts.price == 79 && facts.currency == "USD")
    }

    @Test("A listing page with several products isn't a product")
    func listing() {
        let html = #"<script type="application/ld+json">{"@type":"ItemList","itemListElement":[{"@type":"Product","offers":{"price":79}},{"@type":"Product","offers":{"price":59}}]}</script>"#
        #expect(PageReader.read(html: html).price == nil)
    }

    @Test("A price comes from og:price or product:price meta tags")
    func priceMeta() {
        let html = #"<meta property="product:price:amount" content="42,50"><meta property="product:price:currency" content="EUR">"#
        let facts = PageReader.read(html: html)
        #expect(facts.kind == .product && facts.price == 42.5 && facts.currency == "EUR")
        let og = #"<meta property='og:price:amount' content='1,299'><meta property='og:price:currency' content='GBP'>"#
        #expect(PageReader.read(html: og).price == 1299)
    }

    @Test("A recipe is recognized from schema.org Recipe")
    func recipe() {
        let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Pastéis de nata"}</script><body>short</body>"#
        #expect(PageReader.read(html: html).isRecipe)
    }

    @Test("An article's read time comes from its word count, about 230 words a minute")
    func readTime() {
        let words = Array(repeating: "word", count: 2300).joined(separator: " ")
        let html = "<html><body><nav>Home About Contact</nav><article><h1>Title</h1><p>\(words)</p></article><script>var a = 1</script></body></html>"
        let facts = PageReader.read(html: html)
        #expect(facts.kind == .article && facts.minutes == 10)
        #expect(PageReader.readMinutes(words: 230) == 1 && PageReader.readMinutes(words: 3000) == 13 && PageReader.readMinutes(words: 20) == 1)
    }

    @Test("A page with little text gets no read time")
    func shortPage() {
        let facts = PageReader.read(html: "<body><p>Sign in to continue.</p></body>")
        #expect(facts.kind == nil && facts.minutes == nil)
    }

    @Test("JSON-LD wordCount wins over counting")
    func declaredWords() {
        let html = #"<script type="application/ld+json">{"@type":"NewsArticle","wordCount":"4600"}</script><body>tiny</body>"#
        #expect(PageReader.read(html: html).minutes == 20)
    }

    @Test("Card badges", arguments: [(13, "13 min"), (60, "1 h"), (65, "1 h 5 min"), (0, "1 min")])
    func minutesBadge(minutes: Int, text: String) {
        #expect(Badges.minutes(minutes) == text)
    }

    @Test("Price badges drop decimals on whole amounts")
    func priceBadge() {
        let locale = Locale(identifier: "en_IE")
        #expect(Badges.price(189, currency: "EUR", locale: locale) == "€189")
        #expect(Badges.price(59.9, currency: "USD", locale: Locale(identifier: "en_US")) == "$59.90")
    }
}

struct PlaceLinkTests {
    @Test("Places come from Apple Maps and Google Maps links", arguments: [
        "https://maps.apple.com/?q=Miradouro&ll=38.71,-9.13",
        "https://www.google.com/maps/place/Miradouro+da+Senhora+do+Monte",
        "https://maps.google.com/?q=Lisbon",
        "https://maps.app.goo.gl/AbC123",
        "https://goo.gl/maps/xyz",
    ])
    func place(link: String) {
        #expect(Links.kind(URL(string: link)!) == .place)
    }
}
