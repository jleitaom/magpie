import Foundation
import Testing
@testable import MagpieKit

struct BookmarksTests {
    // The shape Chrome, Firefox and Safari export.
    static let html = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 ADD_DATE="1700000000" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
        <DL><p>
            <DT><A HREF="https://www.inkandswitch.com/local-first/" ADD_DATE="1700000100">Local-first software</A>
            <DT><H3>Recipes &amp; food</H3>
            <DL><p>
                <DT><A HREF="https://www.seriouseats.com/nata" ADD_DATE="1700000200">Pastéis de nata</A>
                <DT><A HREF="https://cooking.nytimes.com/x">Bread</A>
            </DL><p>
        </DL><p>
        <DT><H3>Watch later</H3>
        <DL><p>
            <DT><A HREF="https://www.youtube.com/watch?v=abc">Espresso</A>
            <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
        </DL><p>
        <DT><A HREF="https://example.com/loose">Loose link</A>
    </DL><p>
    """

    @Test("It parses nested folders and their links")
    func parse() {
        let root = BookmarkFile.parse(Self.html)
        #expect(root.folders.map(\.name) == ["Bookmarks Bar", "Watch later"])
        #expect(root.links.map(\.title) == ["Loose link"])
        let bar = root.folders[0]
        #expect(bar.links.map(\.title) == ["Local-first software"])
        #expect(bar.folders.first?.name == "Recipes & food" && bar.folders.first?.links.count == 2)
        #expect(bar.folders.first?.id == "Bookmarks Bar/Recipes & food")
        #expect(root.total == 5)
        #expect(bar.links.first?.added == Date(timeIntervalSince1970: 1_700_000_100))
    }

    @Test("Only web links are kept (no bookmarklets)")
    func webOnly() {
        let watch = BookmarkFile.parse(Self.html).folders[1]
        #expect(watch.links.map(\.title) == ["Espresso"])
    }

    @Test("The tree lists every folder with its depth")
    func flattened() {
        let rows = BookmarkFile.parse(Self.html).flattened()
        #expect(rows.map(\.folder.name) == ["Bookmarks Bar", "Recipes & food", "Watch later"])
        #expect(rows.map(\.depth) == [0, 1, 0])
    }

    @Test("Duplicates are skipped and counted; only chosen folders are imported")
    func plan() {
        let root = BookmarkFile.parse(Self.html)
        let existing: Set<String> = [Links.normalize(URL(string: "http://inkandswitch.com/local-first")!)]
        let plan = BookmarkFile.plan(root, folders: ["Bookmarks Bar", "Bookmarks Bar/Recipes & food"], includeLoose: true, existing: existing)
        #expect(plan.duplicates == 1)
        #expect(plan.items.map(\.link.title) == ["Loose link", "Pastéis de nata", "Bread"])
        #expect(plan.items[1].folder == ["Bookmarks Bar", "Recipes & food"] && plan.items[0].folder.isEmpty)
    }
}
