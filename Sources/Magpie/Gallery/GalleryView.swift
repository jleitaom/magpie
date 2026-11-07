import AppKit
import MagpieKit
import SwiftUI

/// The Gallery: cards in masonry columns. Each column is a LazyVStack, so only the
/// cards on screen are built, even with thousands of blocks.
struct GalleryView: View {
    let blocks: [Block]
    /// The Inbox shows "N blocks waiting to be sorted" with a Start sorting button above its cards.
    var sortPrompt: Int = 0
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @FocusState private var hasFocus: Bool

    static let minColumn: CGFloat = 220
    static let margin: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width - Self.margin * 2)
            let count = Masonry.columnCount(width: width, minColumn: Self.minColumn, gap: Metric.cardGap)
            let columnWidth = CGFloat(Masonry.columnWidth(width: width, count: count, gap: Metric.cardGap))
            let heights = blocks.map { CardLayout.estimatedHeight($0, width: columnWidth) }
            let columns = Masonry.columns(heights: heights, count: count, gap: Metric.cardGap)

            ScrollView {
                VStack(spacing: Space.lg) {
                if sortPrompt > 0 {
                    KitBanner(title: "\(sortPrompt) \(sortPrompt == 1 ? "block" : "blocks") waiting to be sorted",
                              detail: "Sort them one at a time, from the keyboard. About a minute.",
                              action: "Start sorting") { model.startSorting() }
                }
                HStack(alignment: .top, spacing: Metric.cardGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, indexes in
                        LazyVStack(spacing: Metric.cardGap) {
                            ForEach(indexes, id: \.self) { index in
                                BlockCard(block: blocks[index], width: columnWidth)
                            }
                        }
                        .frame(width: columnWidth)
                    }
                }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, Metric.barHeight + Space.sm)
                .padding(.bottom, Space.section * 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        // Focused from the start, so ⌫ and Return work right away (and snapshots show the focused state).
        .onAppear { hasFocus = true }
        .onDeleteCommand {
            if let selection = model.selection { model.delete([selection], undo: undoManager) }
        }
        .onKeyPress(.return) {
            guard let block = model.block(model.selection) else { return .ignored }
            model.open(block)
            return .handled
        }
        .onKeyPress(.escape) {
            guard model.selection != nil else { return .ignored }
            model.selection = nil
            return .handled
        }
    }
}

/// One card in the Gallery.
struct BlockCard: View {
    let block: Block
    let width: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let isSelected = model.selection == block.uid
        Button {
            model.selection = isSelected ? nil : block.uid
        } label: {
            BlockCardView(content: CardLayout.content(for: block, width: width))
        }
        .buttonStyle(BlockCardStyle(tint: block.tint, isSelected: isSelected))
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(block) })
        .contextMenu { BlockMenu(block: block) }
        .help(block.url?.absoluteString ?? block.title)
    }
}

/// The right-click menu for a block (also used in the details panel's ⋯ button).
struct BlockMenu: View {
    let block: Block
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if block.url != nil {
            Button("Open") { model.open(block) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(block.urlString ?? "", forType: .string)
            }
            Divider()
        }
        Menu("Move to") {
            Button("Inbox") { model.move(block, to: nil, undo: undoManager) }
                .disabled(block.collection == nil)
            Divider()
            ForEach(model.collections) { target in
                Button(target.name) { model.move(block, to: target, undo: undoManager) }
                    .disabled(block.collection?.uid == target.uid)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete([block.uid], undo: undoManager) }
    }
}

/// Turns a Block into what a card shows, and estimates its height for the masonry.
enum CardLayout {
    static func thumbHeight(_ block: Block, width: CGFloat) -> CGFloat {
        let aspect = block.thumbnailAspect > 0 ? block.thumbnailAspect : 16.0 / 10
        return min(max(width / aspect, width * 0.55), width * 1.35)
    }

    static func content(for block: Block, width: CGFloat) -> CardContent {
        let body: CardContent.Body
        var height = thumbHeight(block, width: width)
        switch block.kind {
        case .note:
            body = .note(block.bodyText)
        case .checklist:
            body = .checklist(block.checklist.filter { !$0.text.isEmpty }.map { .init(text: $0.text, done: $0.done) })
        case .place where block.thumbnail == nil:
            body = .place
            height = width * 0.62
        default:
            if let data = block.thumbnail, let image = ThumbnailCache.image(for: block.uid, data: data) {
                body = .visual(.image(image))
            } else if block.enrich == .pending {
                body = .visual(.loading)
                height = width * 0.5
            } else {
                body = .plain
            }
        }
        return CardContent(body: body, kindLabel: block.kind.label, title: block.title.isEmpty ? "Untitled" : block.title,
                           site: block.siteName, badge: nil, tint: block.tint, thumbHeight: height)
    }

    /// A close guess of the card's height, so columns come out even before cards render.
    static func estimatedHeight(_ block: Block, width: CGFloat) -> Double {
        let content = content(for: block, width: width)
        let textWidth = max(width - Metric.cardPadding * 2, 60)
        func lines(_ text: String, charWidth: CGFloat, max limit: Int) -> CGFloat {
            CGFloat(min(limit, max(1, Int((CGFloat(text.count) * charWidth / textWidth).rounded(.up)))))
        }
        var height = Metric.cardPadding * 2 + 14 + 6 + lines(content.title, charWidth: 7.6, max: 3) * 18 + 6 + 16 // grid: ok text-size estimate
        switch content.body {
        case .visual, .place: height += content.thumbHeight
        case .note(let text): height += 6 + lines(text, charWidth: 6.8, max: 6) * 17 // grid: ok text-size estimate
        case .checklist(let items): height += 8 + CGFloat(min(items.count, 4)) * 22
        case .plain: break
        }
        return Double(height)
    }
}

/// Decoded thumbnails, so scrolling never decodes the same JPEG twice.
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    static func image(for uid: UUID, data: Data) -> NSImage? {
        let key = "\(uid.uuidString)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
