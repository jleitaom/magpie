import Foundation
import Testing
@testable import MagpieKit

struct SearchTests {
    let index = Search.index(["Café Santiago, Lisbon", "francesinha-guide", nil, "#Porto"])

    @Test("Search ignores case and accents")
    func folding() {
        #expect(Search.matches(index: index, terms: Search.terms("CAFE")))
        #expect(Search.matches(index: index, terms: Search.terms("lisbon")))
        #expect(Search.matches(index: Search.index(["Lisbon"]), terms: Search.terms("LÍSBON")))
    }

    @Test("Search matches the start of words, every word typed")
    func prefixes() {
        #expect(Search.matches(index: index, terms: Search.terms("caf lis")))
        #expect(Search.matches(index: index, terms: Search.terms("franc")))
        #expect(Search.matches(index: index, terms: Search.terms("guide")))
        #expect(!Search.matches(index: index, terms: Search.terms("isbon")))
        #expect(!Search.matches(index: index, terms: Search.terms("cafe tokyo")))
        #expect(!Search.matches(index: index, terms: Search.terms("   ")))
    }

    @Test("Matching words are found for highlighting")
    func highlight() {
        let text = "Café in Lisbon, a cafeteria guide"
        let ranges = Search.ranges(in: text, terms: Search.terms("cafe lis"))
        #expect(ranges.map { String(text[$0]) } == ["Café", "Lis", "cafe"])
    }

    @Test("5,000 blocks search well under 100 ms")
    func speed() {
        let indexes = (0..<5000).map { Search.index(["Block number \($0) about vinyl records", "site\($0 % 50).com", "note \($0)"]) }
        let start = Date()
        let hits = indexes.filter { Search.matches(index: $0, terms: Search.terms("vin site4")) }
        let elapsed = Date().timeIntervalSince(start)
        #expect(hits.count == 1100 && elapsed < 0.1)
    }
}

struct TotalsTests {
    @Test("Totals are kept per currency when currencies differ")
    func perCurrency() {
        let locale = Locale(identifier: "en_IE")
        #expect(Totals.money([(189, "EUR"), (253, "EUR"), (60, "USD")], fallback: "EUR", locale: locale) == "€442 + US$60")
        #expect(Totals.money([(64, nil), (129, "EUR")], fallback: "EUR", locale: locale) == "€193")
    }
}
