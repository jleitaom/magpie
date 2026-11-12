import AppKit
import MagpieKit
import SwiftUI

/// The Gallery: cards in masonry columns. Each column is a LazyVStack, so only the
/// cards on screen are built, even with thousands of blocks.
struct GalleryView: View {
    let blocks: [Block]
    /// The Inbox shows "N blocks waiting to be sorted" with a Start sorting button above its cards.
    var sortPrompt: Int = 0
    /// The collection's totals strip (S-073, S-074), when it has lengths or prices.
    var videoTotal: String?
    var priceTotal: String?
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @FocusState private var hasFocus: Bool
    /// The card being dragged into a new place, and the one it's over (S-066).
    @State private var dragging: UUID?
    @State private var dropTarget: UUID?
    /// The last layout, for the arrow keys (S-032). A box, so updating it never redraws.
    @State private var layout = LayoutBox()

    final class LayoutBox {
        var columns: [[Int]] = []
        var heights: [Double] = []
    }

    static let minColumn: CGFloat = 220
    static let margin: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width - Self.margin * 2)
            let count = Masonry.columnCount(width: width, minColumn: Self.minColumn, gap: Metric.cardGap)
            let columnWidth = CGFloat(Masonry.columnWidth(width: width, count: count, gap: Metric.cardGap))
            let heights = blocks.map { CardLayout.estimatedHeight($0, width: columnWidth) }
            let columns = Masonry.columns(heights: heights, count: count, gap: Metric.cardGap)
            let _ = { layout.columns = columns; layout.heights = heights }()

            ScrollView {
                VStack(spacing: Space.lg) {
                if videoTotal != nil || priceTotal != nil {
                    @Bindable var model = model
                    KitTotalsStrip(videoTotal: videoTotal, priceTotal: priceTotal, fitsTwenty: $model.fitsTwentyMinutes)
                }
                if sortPrompt > 0 {
                    KitBanner(title: "\(sortPrompt) \(sortPrompt == 1 ? "block" : "blocks") waiting to be sorted",
                              detail: "Sort them one at a time, from the keyboard. About a minute.",
                              action: "Start sorting") { model.startSorting() }
                }
                HStack(alignment: .top, spacing: Metric.cardGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, indexes in
                        LazyVStack(spacing: Metric.cardGap) {
                            // Cards are identified by their block, not their position: after a delete
                            // every later index shifts, and position-based identity mixed cards up.
                            ForEach(indexes.map { blocks[$0] }, id: \.uid) { block in
                                BlockCard(block: block, width: columnWidth, isDropTarget: dropTarget == block.uid)
                                    .reorderable(block, shown: blocks, model: model, dragging: $dragging, target: $dropTarget)
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
        // Edit → Copy (⌘C) copies the selected card's link, or a note's text.
        .onCopyCommand {
            guard let block = model.block(model.selection) else { return [] }
            model.copy(block)
            return []
        }
        .onDeleteCommand {
            if let selection = model.selection { model.delete([selection], undo: undoManager) }
        }
        .onKeyPress(.return) {
            guard let block = model.block(model.selection) else { return .ignored }
            model.open(block)
            return .handled
        }
        // T: tag the selected card (the details panel opens with the cursor in its tag field).
        .onKeyPress("t") {
            guard model.selection != nil else { return .ignored }
            model.focusTagField = true
            return .handled
        }
        // Arrow keys move the selection: up and down in a column, left and right across (S-032).
        .onKeyPress(.upArrow) { step(.up) }
        .onKeyPress(.downArrow) { step(.down) }
        .onKeyPress(.leftArrow) { step(.left) }
        .onKeyPress(.rightArrow) { step(.right) }
        .onKeyPress(.space) {
            guard model.selection != nil else { return .ignored }
            model.quickLook(model.block(model.selection))
            return .handled
        }
        .onKeyPress(.escape) {
            guard model.selection != nil else { return .ignored }
            model.selection = nil
            return .handled
        }
    }
}

extension GalleryView {
    private func step(_ direction: GridNavigation.Direction) -> KeyPress.Result {
        guard !blocks.isEmpty else { return .ignored }
        guard let current = blocks.firstIndex(where: { $0.uid == model.selection }) else {
            model.selection = blocks[0].uid
            return .handled
        }
        if let next = GridNavigation.next(from: current, direction, columns: layout.columns, heights: layout.heights,
                                          gap: Double(Metric.cardGap)) {
            model.selection = blocks[next].uid
        }
        return .handled
    }
}

/// One card in the Gallery.
struct BlockCard: View {
    let block: Block
    let width: CGFloat
    /// A card being dragged is over this one: it shows where it will land.
    var isDropTarget = false
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if block.isGone { EmptyView() } else { live }
    }

    @ViewBuilder private var live: some View {
        let isSelected = model.selection == block.uid
        Button {
            model.selection = isSelected ? nil : block.uid
        } label: {
            BlockCardView(content: CardLayout.content(for: block, width: width, highlightQuery: model.isSearching ? model.searchQuery : ""))
        }
        .buttonStyle(BlockCardStyle(tint: block.tint, isSelected: isSelected || isDropTarget))
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

    /// The right-click menu for a block, the same wherever it shows: Gallery, Journal, Sort Inbox,
    /// Lucky Dip, Rediscover (S-051). Shortcuts match the menu bar's Block menu.
    var body: some View {
        if block.isGone { EmptyView() } else { items }
    }

    @ViewBuilder private var items: some View {
        if block.url != nil {
            Button("Open") { model.open(block) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        if block.url != nil || block.thumbnail != nil {
            Button("Quick Look") { model.quickLook(block) }
                .keyboardShortcut("y")
        }
        Button(block.url != nil ? "Copy Link" : "Copy") { model.copy(block) }
            .keyboardShortcut("c")
        if model.canChoosePicture(block) {
            Button("Choose Picture…") { model.choosePicture(block) }
                .keyboardShortcut("p", modifiers: [.command, .option])
        }
        Button("Show Details") { model.selection = block.uid; if model.viewMode != .journal { model.show(.gallery) } }
        Divider()
        if model.canChangeKind(block) {
            Menu("Kind") {
                ForEach(Array(BlockKind.choosable.enumerated()), id: \.element) { index, kind in
                    Toggle(kind.label, isOn: Binding(get: { block.kind == kind },
                                                     set: { if $0 { model.setKind(kind, for: block, undo: undoManager) } }))
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control, .option, .command])
                }
            }
        }
        Menu("Move to") {
            Button("Inbox") { model.move(block, to: nil, undo: undoManager) }
                .disabled(block.collection == nil && block.status == .inbox)
            Divider()
            ForEach(model.collectionTree, id: \.collection.uid) { row in
                Button(String(repeating: "    ", count: row.depth) + row.collection.name) {
                    model.move(block, to: row.collection, undo: undoManager)
                }
                .disabled(block.collection?.uid == row.collection.uid)
            }
        }
        Menu("Tags") {
            ForEach(model.tags, id: \.uid) { tag in
                Toggle(tag.name, isOn: Binding(
                    get: { (block.tags ?? []).contains { $0.uid == tag.uid } },
                    set: { on in if on { model.addTags(tag.name, to: block) } else { model.removeTag(tag, from: block) } }
                ))
            }
            if !model.tags.isEmpty { Divider() }
            Button("New Tag…") {
                model.selection = block.uid
                model.focusTagField = true
            }
            .keyboardShortcut("t")
        }
        Divider()
        if Expiry.label(block.expiresAt, now: .now) != nil {
            Button("Keep (Don’t Expire)") { model.keep(block) }
        }
        if block.status == .archived {
            Button("Unarchive") { model.unarchive(block) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        } else {
            Button("Archive") { model.archive(block, undo: undoManager) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        Button("Delete", role: .destructive) { model.delete([block.uid], undo: undoManager) }
            .keyboardShortcut(.delete, modifiers: [])
    }
}

/// Turns a Block into what a card shows, and estimates its height for the masonry.
enum CardLayout {
    static func thumbHeight(_ block: Block, width: CGFloat) -> CGFloat {
        let aspect = block.thumbnailAspect > 0 ? block.thumbnailAspect : 16.0 / 10
        return min(max(width / aspect, width * 0.55), width * 1.35)
    }

    static func content(for block: Block, width: CGFloat, highlightQuery: String = "") -> CardContent {
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
                           site: block.siteName, badge: block.badge, tint: block.tint, thumbHeight: height,
                           warning: Expiry.label(block.expiresAt, now: .now), highlight: Search.terms(highlightQuery))
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
