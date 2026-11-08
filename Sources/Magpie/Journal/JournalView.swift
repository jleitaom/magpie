import MagpieKit
import SwiftUI

/// The Journal (S-067): the same blocks as the Gallery, as a dense numbered list. Clicking the
/// Title, Length or Saved header sorts by it (S-065). Click a row for its details, double-click
/// or Return to open it, ↑ and ↓ to move.
struct JournalView: View {
    let blocks: [Block]
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @FocusState private var hasFocus: Bool

    var body: some View {
        let order = model.order(for: model.scope)
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        let dot = Text(".").foregroundStyle(Ink.accentText)
                        Text("\(model.isSearching && !model.searchTerms.isEmpty ? "Search" : model.placeName(model.scope))\(dot)")
                            .kitType(.display).foregroundStyle(Ink.text)
                        Spacer()
                        Text("\(blocks.count) \(blocks.count == 1 ? "BLOCK" : "BLOCKS") · SORTED BY \(order.label.uppercased())")
                            .kitType(.mono).foregroundStyle(Ink.secondary)
                    }
                    .padding(.bottom, Space.md)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.text).frame(height: 1) }
                    header(order)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.element.uid) { index, block in
                            JournalRow(number: index + 1, block: block, isSelected: model.selection == block.uid)
                                .id(block.uid)
                        }
                    }
                }
                .padding(.horizontal, Space.section + Space.sm)
                // Make room for the details panel, so it never covers the columns.
                .padding(.trailing, model.selection == nil ? 0 : Metric.panelWidth + Space.lg)
                .animation(Motion.panel, value: model.selection == nil)
                .padding(.top, Metric.barHeight + Space.lg)
                .padding(.bottom, Space.section * 3)
            }
            .onChange(of: model.selection) { _, uid in
                if let uid { withAnimation(nil) { scroller.scrollTo(uid) } }
            }
        }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onAppear { hasFocus = true }
        .onCopyCommand {
            if let block = model.block(model.selection) { model.copy(block) }
            return []
        }
        .onDeleteCommand {
            if let selection = model.selection { model.delete([selection], undo: undoManager) }
        }
        .onKeyPress(.downArrow) { step(1) }
        .onKeyPress(.upArrow) { step(-1) }
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
        .onKeyPress("t") {
            guard model.selection != nil else { return .ignored }
            model.focusTagField = true
            return .handled
        }
    }

    /// ↑ and ↓ move the selection; the first press picks the first row.
    private func step(_ by: Int) -> KeyPress.Result {
        guard !blocks.isEmpty else { return .ignored }
        let index = blocks.firstIndex { $0.uid == model.selection }.map { min(max($0 + by, 0), blocks.count - 1) } ?? 0
        model.selection = blocks[index].uid
        return .handled
    }

    private func header(_ order: BlockOrder) -> some View {
        JournalColumns(widths: JournalColumns.widths, gap: Space.lg) {
            Text("NO.")
            Color.clear
            headButton("TITLE", on: order == .title) { model.setOrder(.title, for: model.scope) }
            headButton("LENGTH", on: order == .quickest) { model.setOrder(.quickest, for: model.scope) }
            Text("COLLECTION")
            headButton(order == .oldest ? "SAVED ↑" : "SAVED ↓", on: order == .newest || order == .oldest, trailing: true) {
                model.setOrder(order == .newest ? .oldest : .newest, for: model.scope)
            }
        }
        .kitType(.mono)
        .foregroundStyle(Ink.secondary)
        .frame(height: Metric.journalHeader)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }

    private func headButton(_ title: String, on: Bool, trailing: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).foregroundStyle(on ? Ink.accentText : Ink.secondary)
                .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Sort by \(title.lowercased())")
    }
}

/// One row: number, color dot, title, length, collection, saved date. Selected: inverted.
private struct JournalRow: View {
    let number: Int
    let block: Block
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let ink = isSelected ? Ink.onChosen : Ink.text
        let quiet = isSelected ? Ink.onChosen.opacity(0.7) : Ink.secondary
        JournalColumns(widths: JournalColumns.widths, gap: Space.lg) {
            Text(String(format: "%02d", number)).kitType(.mono).foregroundStyle(quiet)
            Circle().fill(block.tint.map(Ink.swatch) ?? Ink.tertiary).frame(width: Metric.tagDot, height: Metric.tagDot)
            Text(Highlight.text(block.title.isEmpty ? "Untitled" : block.title, terms: model.searchTerms))
                .kitType(.label).foregroundStyle(ink).lineLimit(1)
            Text(block.badge?.uppercased() ?? "—").kitType(.mono).foregroundStyle(quiet).lineLimit(1)
            Text(block.collection?.name ?? (block.status == .inbox ? "Inbox" : "—")).kitType(.meta).foregroundStyle(quiet).lineLimit(1)
            Text(block.createdAt.formatted(.dateTime.day().month(.abbreviated))).kitType(.mono).foregroundStyle(quiet)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: Metric.journalRow)
        .padding(.horizontal, Metric.rowInset)
        .background(isSelected ? Ink.chosen : hovering ? Ink.hover : .clear)
        .padding(.horizontal, -Metric.rowInset)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.open(block) }
        .onTapGesture { model.selection = isSelected ? nil : block.uid }
        .onHover { hovering = $0 }
        .contextMenu { BlockMenu(block: block) }
        .help(block.url?.absoluteString ?? block.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The Journal's columns, shared by the header and the rows so they line up.
private struct JournalColumns: Layout {
    /// No., dot, title (nil: the rest), length, collection, saved.
    let widths: [CGFloat?]
    let gap: CGFloat

    @MainActor static var widths: [CGFloat?] {
        [Metric.journalNumber, Metric.tagDot, nil, Metric.journalLength, Metric.journalCollection, Metric.journalSaved]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 600, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fixed = widths
        let taken = fixed.compactMap { $0 }.reduce(0, +) + gap * CGFloat(fixed.count - 1)
        let flexible = max(bounds.width - taken, 80)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() where index < fixed.count {
            let width = fixed[index] ?? flexible
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + gap
        }
    }
}
