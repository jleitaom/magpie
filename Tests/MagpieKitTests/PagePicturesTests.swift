import Foundation
import Testing
@testable import MagpieKit

struct PagePicturesTests {
    let base = URL(string: "https://shop.example.com/lamps/brass-desk-lamp")!

    @Test("Share pictures come first, then structured data, then content images")
    func order() {
        let html = """
        <html><head>
        <meta property="og:image" content="https://cdn.example.com/lamp-hero.jpg">
        <meta property="og:image" content="/img/lamp-side.jpg">
        <meta name="twitter:image" content="https://cdn.example.com/lamp-hero.jpg">
        <script type="application/ld+json">{"@type":"Product","image":["https://cdn.example.com/lamp-studio.jpg",{"@type":"ImageObject","url":"https://cdn.example.com/lamp-detail.jpg"}]}</script>
        </head><body>
        <img src="/img/logo.png" width="120">
        <img src="/img/lamp-room.jpg" width="800" height="600">
        <img srcset="/img/lamp-night-400.jpg 400w, /img/lamp-night-1200.jpg 1200w" src="/img/lamp-night-400.jpg">
        <img data-src="/img/lamp-lazy.jpg">
        </body></html>
        """
        #expect(PagePictures.candidates(html: html, base: base).map(\.absoluteString) == [
            "https://cdn.example.com/lamp-hero.jpg",
            "https://shop.example.com/img/lamp-side.jpg",
            "https://cdn.example.com/lamp-studio.jpg",
            "https://cdn.example.com/lamp-detail.jpg",
            "https://shop.example.com/img/lamp-room.jpg",
            "https://shop.example.com/img/lamp-night-1200.jpg",
            "https://shop.example.com/img/lamp-lazy.jpg",
        ])
    }

    @Test("Icons, logos, avatars, tiny images, SVG and GIFs are left out")
    func chrome() {
        let html = """
        <img src="/static/site-logo.jpg"><img src="/favicon.ico"><img src="/u/avatars/me.jpg">
        <img src="/img/arrow.svg"><img src="/t/pixel.gif"><img src="/img/thumb.jpg" width="48" height="48">
        """
        #expect(PagePictures.candidates(html: html, base: base).isEmpty)
    }

    @Test("Only web addresses: a page can't point Magpie at a local file")
    func webOnly() {
        let html = """
        <meta property="og:image" content="file:///Users/me/Pictures/private.jpg">
        <img src="data:image/png;base64,AAAA"><img src="ftp://example.com/a.jpg">
        <img src="//cdn.example.com/protocol-relative.jpg">
        """
        #expect(PagePictures.candidates(html: html, base: base).map(\.absoluteString) == ["https://cdn.example.com/protocol-relative.jpg"])
    }

    @Test("No more than the limit")
    func limit() {
        let html = (1...40).map { "<img src=\"/p/\($0).jpg\">" }.joined()
        #expect(PagePictures.candidates(html: html, base: base).count == PagePictures.limit)
    }

    @Test("The largest picture in a srcset")
    func srcset() {
        #expect(PagePictures.largest(inSrcset: "a.jpg 1x, b.jpg 2x") == "b.jpg")
        #expect(PagePictures.largest(inSrcset: "small.jpg 320w, big.jpg 1280w, mid.jpg 640w") == "big.jpg")
        #expect(PagePictures.largest(inSrcset: nil) == nil)
    }
}
