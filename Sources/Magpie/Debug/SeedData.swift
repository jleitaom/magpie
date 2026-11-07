import AppKit
import MagpieKit
import SwiftData

/// Sample library for snapshots and demos: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with the mockup's blocks. Everything here is something a person can make in the app:
/// links (with the preview images a page would give), notes, checklists, collections, pins.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Block>())) ?? 0) == 0 else { return }

        var collections: [String: BlockCollection] = [:]
        for name in ["Reading", "Watch later", "Shopping", "Ideas", "Vinyl", "Lisbon trip", "Recipes"] {
            collections[name] = model.createCollection(named: name)
        }
        // Five past days of Inbox zero, so the top bar shows a streak.
        let today = DayActivity.number(for: .now)
        for back in 1...5 {
            let day = DayActivity(day: today - back)
            day.saved = 3
            day.sorted = 3
            day.reachedInboxZero = true
            // A Lucky Dip pick finished on each of the last 4 days.
            day.finished = back <= 4 ? 1 : 0
            context.insert(day)
        }
        model.refreshStreak()
        model.refreshDipStats()
        // One nested collection, so the Collections panel shows the tree.
        if let trip = collections["Lisbon trip"], let ideas = collections["Ideas"] { model.place(trip, .inside(ideas.uid)) }

        let now = Date.now
        for (index, sample) in samples.reversed().enumerated() {
            let block = Block(kind: sample.kind, title: sample.title)
            block.siteName = sample.site
            if let url = sample.url.flatMap(URL.init(string:)) {
                block.urlString = url.absoluteString
                block.normalizedURL = Links.normalize(url)
            }
            block.bodyText = sample.text ?? ""
            block.minutes = sample.minutes
            if let price = sample.price {
                block.price = price
                block.currency = "EUR"
            }
            block.isRecipe = sample.recipe
            if let items = sample.checklist { block.checklist = items }
            if let art = sample.art, let image = render(art) {
                block.thumbnail = image.data
                block.thumbnailAspect = art.aspect
                block.colorHex = image.color.map(Int.init)
            }
            if let name = sample.collection, let target = collections[name] {
                block.collection = target
                block.status = .kept
            } else {
                block.status = .inbox
            }
            block.createdAt = now.addingTimeInterval(Double(-(samples.count - index)) * 3_000)
            context.insert(block)
        }
        model.save()
    }

    // MARK: - Samples (the mockup's content)

    private struct Art {
        var background: UInt32, shape: UInt32, size: Double, shapeAspect: Double = 1, round = true, aspect: Double
    }

    private struct Sample {
        var kind: BlockKind, title: String, site: String, url: String?
        var collection: String? = nil, text: String? = nil, checklist: [ChecklistItem]? = nil, art: Art? = nil
        /// What S-063 would read from the page: watch or read time, price.
        var minutes: Int? = nil, price: Double? = nil, recipe = false
    }

    private static let samples: [Sample] = [
        Sample(kind: .link, title: "Local-first software: you own your data, in spite of the cloud", site: "inkandswitch.com",
               url: "https://www.inkandswitch.com/local-first/", art: Art(background: 0xE9E5DC, shape: 0x1E1E1E, size: 0.34, round: false, aspect: 1.6), minutes: 34),
        Sample(kind: .video, title: "How to make Neapolitan pizza at home in a regular oven", site: "youtube.com",
               url: "https://www.youtube.com/watch?v=sample-pizza", art: Art(background: 0xF3D9BD, shape: 0xC8553D, size: 0.58, aspect: 1.78), minutes: 13),
        Sample(kind: .product, title: "Desk lamp, brass", site: "nordicnest.com", url: "https://www.nordicnest.com/sample-lamp",
               art: Art(background: 0xEDEBE7, shape: 0xD9A441, size: 0.48, aspect: 1), price: 189),
        Sample(kind: .place, title: "Miradouro da Senhora do Monte", site: "maps.apple.com", url: "https://maps.apple.com/?q=Miradouro+da+Senhora+do+Monte"),
        Sample(kind: .note, title: "Gift idea for Ana", site: "Note", url: nil,
               text: "A Japanese pressing of Kind of Blue, the one with the obi strip. Check Flur in Cais do Sodré."),
        Sample(kind: .link, title: "Kind of Blue – 1959 original pressing", site: "discogs.com", url: "https://www.discogs.com/release/sample-kob",
               art: Art(background: 0x1F3A5F, shape: 0x0B0B0C, size: 0.78, aspect: 1)),
        Sample(kind: .video, title: "The making of a typeface that changed how we read signs", site: "vimeo.com", url: "https://vimeo.com/sample",
               art: Art(background: 0x26262A, shape: 0xF2F2F2, size: 0.2, shapeAspect: 3, round: false, aspect: 1.78), minutes: 22),
        Sample(kind: .image, title: "Japandi shelf styling", site: "pinterest.com", url: "https://www.pinterest.com/pin/sample",
               art: Art(background: 0xE3E9DF, shape: 0x7A8F6A, size: 0.7, shapeAspect: 0.75, round: false, aspect: 0.75)),
        Sample(kind: .video, title: "Lisbon in 4K — a slow walk through Alfama", site: "youtube.com", url: "https://www.youtube.com/watch?v=sample-alfama",
               collection: "Watch later", art: Art(background: 0xF2DE9B, shape: 0x3E7CB1, size: 0.4, shapeAspect: 2, aspect: 1.78), minutes: 47),
        Sample(kind: .video, title: "How espresso actually works", site: "youtube.com", url: "https://www.youtube.com/watch?v=sample-espresso",
               collection: "Watch later", art: Art(background: 0x3B2A22, shape: 0xC8A27A, size: 0.46, aspect: 1.78), minutes: 18),
        Sample(kind: .product, title: "Ceramic pour-over set", site: "etsy.com", url: "https://www.etsy.com/listing/sample-pourover",
               collection: "Shopping", art: Art(background: 0xE8D8CC, shape: 0xA86E52, size: 0.5, shapeAspect: 0.8, aspect: 0.8), price: 64),
        Sample(kind: .product, title: "Wool throw, oat", site: "hay.dk", url: "https://hay.dk/sample-throw",
               collection: "Shopping", art: Art(background: 0xE6DFD1, shape: 0xB5A588, size: 0.56, shapeAspect: 1.5, round: false, aspect: 1.5), price: 129),
        Sample(kind: .checklist, title: "Lisbon weekend", site: "Checklist", url: nil, collection: "Ideas",
               checklist: [ChecklistItem(text: "Book the train", done: true), ChecklistItem(text: "Time Out Market for lunch"),
                           ChecklistItem(text: "Sunset at Senhora do Monte")]),
        Sample(kind: .note, title: "Living room", site: "Note", url: nil, collection: "Ideas",
               text: "Warm light, fewer things, one big plant. Records on a low shelf."),
        Sample(kind: .link, title: "Blue Train – Blue Note 75 reissue", site: "discogs.com", url: "https://www.discogs.com/release/sample-bluetrain",
               collection: "Vinyl", art: Art(background: 0x2C5D8A, shape: 0x0B0B0C, size: 0.76, aspect: 1)),
        Sample(kind: .link, title: "A Love Supreme – Acoustic Sounds", site: "discogs.com", url: "https://www.discogs.com/release/sample-supreme",
               collection: "Vinyl", art: Art(background: 0x1A1A1A, shape: 0xE6E6E6, size: 0.74, aspect: 1)),
        Sample(kind: .link, title: "How to do great work", site: "paulgraham.com", url: "https://paulgraham.com/greatwork.html",
               collection: "Reading", art: Art(background: 0xEFEDE6, shape: 0x8B2E2E, size: 0.3, shapeAspect: 0.75, round: false, aspect: 1.6), minutes: 42),
        Sample(kind: .link, title: "An architect’s guide to Lisbon", site: "dezeen.com", url: "https://www.dezeen.com/sample-lisbon",
               collection: "Lisbon trip", art: Art(background: 0xF2E6D8, shape: 0xC46A3C, size: 0.44, shapeAspect: 2, aspect: 1.6), minutes: 9),
        Sample(kind: .link, title: "Pastéis de nata at home", site: "seriouseats.com", url: "https://www.seriouseats.com/sample-nata",
               collection: "Recipes", art: Art(background: 0xF3DDA6, shape: 0xB5651D, size: 0.5, aspect: 1.3), minutes: 7, recipe: true),
    ]

    private static func cgColor(_ hex: UInt32) -> CGColor {
        let c = RGB(hex: hex)
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// Draws a flat preview image (a shape on a color field), as a page's preview would be.
    private static func render(_ art: Art) -> (data: Data, color: UInt32?)? {
        let height = 400.0, width = height * art.aspect
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(cgColor(art.background))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let h = height * art.size, w = h * art.shapeAspect
        let rect = CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
        context.setFillColor(cgColor(art.shape))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: art.round ? min(w, h) / 2 : 6,
                               cornerHeight: art.round ? min(w, h) / 2 : 6, transform: nil))
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        return (data, Ingest.mainColor(of: image))
    }
}
