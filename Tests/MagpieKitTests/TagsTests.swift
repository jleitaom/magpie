import Testing
@testable import MagpieKit

struct TagsTests {
    @Test("Tags are case-insensitive: “Jazz” and “jazz” are one tag")
    func caseInsensitive() {
        #expect(Tags.key("Jazz") == Tags.key("jazz"))
        #expect(Tags.key("  #Jazz ") == Tags.key("jazz"))
        #expect(Tags.key("jazz") != Tags.key("jazz funk"))
    }

    @Test("Typed names are tidied", arguments: [("  #vinyl ", "vinyl"), ("##Blue  Note", "Blue Note"), ("#", "")])
    func clean(text: String, name: String) {
        #expect(Tags.clean(text) == name)
    }

    @Test("Several tags at once, separated by commas, without repeats")
    func parse() {
        #expect(Tags.parse("jazz, vinyl, Jazz,, #lisbon ") == ["jazz", "vinyl", "lisbon"])
    }

    @Test("Suggestions: names that start with the text first, then names that contain it")
    func suggestions() {
        let names = ["vinyl", "Jazz", "jazz funk", "acid jazz", "lisbon"]
        #expect(Tags.suggestions(for: "ja", from: names) == ["Jazz", "jazz funk", "acid jazz"])
        #expect(Tags.suggestions(for: "JA", from: names, excluding: ["jazz"]) == ["jazz funk", "acid jazz"])
        #expect(Tags.suggestions(for: "zzz", from: names).isEmpty)
        #expect(Tags.suggestions(for: "", from: names, limit: 2) == ["acid jazz", "Jazz"])
    }
}
