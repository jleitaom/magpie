import MagpieKit
import SwiftData
import SwiftUI

/// Rediscover (S-020): five old saves a day, one big card at a time. K keeps it, A archives it,
/// → skips it (it comes up less often), Return opens it. Menu bar: Rediscover.
struct RediscoverView: View {
    @Environment(AppModel.self) private var model
    @Query private var days: [DayActivity]
    @Query private var blocks: [Block]

    var body: some View {
        let total = model.rediscoverIDs.count
        let done = min(model.todayIfAny?.rediscoverDone ?? 0, total)
        VStack(spacing: 0) {
            if let current = model.rediscoverBlock {
                VStack(spacing: Space.sm) {
                    HStack {
                        Text("Rediscover").kitType(.body).foregroundStyle(Ink.secondary)
                        Spacer()
                        let count = Text("\(done + 1)").foregroundStyle(Ink.text).bold()
                        Text("\(count) of \(total) today").kitType(.body).foregroundStyle(Ink.secondary)
                    }
                    KitProgressBar(value: total == 0 ? 1 : Double(done) / Double(total))
                }
                .frame(width: Metric.sortWidth)
                .padding(.top, Space.md)
                RediscoverCard(block: current, behind: min(total - done - 1, 2))
                    .padding(.top, Space.xxl)
                Spacer(minLength: 0)
            } else {
                Spacer()
                VStack(spacing: Space.sm) {
                    KitIconView(icon: .rediscover, size: Metric.celebrationRing / 3).foregroundStyle(Ink.accentText)
                    Text(total > 0 ? "That’s today’s five." : "Nothing old to rediscover yet.")
                        .kitType(.display).foregroundStyle(Ink.text)
                    Text(total > 0 ? "Come back tomorrow for five more."
                                   : "Blocks come back here \(Rediscover.restDays) days after you last opened them.")
                        .kitType(.body).foregroundStyle(Ink.secondary)
                    Button("Back to Gallery") { model.show(.gallery) }
                        .buttonStyle(.kit(.secondary))
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, Space.sm)
                }
                Spacer()
            }
        }
        .padding(.top, Metric.barHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.rediscoverBlock != nil {
                RediscoverBar().padding(.bottom, Space.xxl)
            }
        }
    }
}

/// The card: picture, how long it's been, title, and the cards still to come behind it.
private struct RediscoverCard: View {
    let block: Block
    let behind: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        if block.isGone { EmptyView() } else { live }
    }

    @ViewBuilder private var live: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radiusSortCard, style: .continuous)
        let content = CardLayout.content(for: block, width: Metric.sortWidth)
        VStack(alignment: .leading, spacing: 0) {
            switch content.body {
            case .visual(let thumb):
                ThumbView(thumb: thumb, badge: content.badge).frame(maxWidth: .infinity).frame(height: Metric.sortHero).clipped()
            case .place:
                MapThumb().frame(maxWidth: .infinity).frame(height: Metric.sortHero).clipped()
            case .note, .checklist, .plain:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: Space.md) {
                Text(meta).kitType(.meta).foregroundStyle(Ink.secondary)
                Text(content.title).kitType(.title).foregroundStyle(Ink.text)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if case .note(let text) = content.body {
                    Text(text).kitType(.body).foregroundStyle(Ink.text.opacity(0.85)).lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !block.note.isEmpty {
                    Text("“\(block.note)”").kitType(.body).foregroundStyle(Ink.secondary).lineLimit(3)
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.xl)
        }
        .frame(width: Metric.sortWidth, alignment: .leading)
        .background(Ink.card(tint: block.tint))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.hairline))
        .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                ForEach((0..<max(behind, 0)).reversed(), id: \.self) { index in
                    let step = Metric.stackStep * CGFloat(index + 1)
                    shape.fill(index == 0 ? Ink.surface : Ink.control)
                        .overlay(shape.strokeBorder(Ink.hairline))
                        .padding(.horizontal, step * 2)
                        .offset(y: step) // grid: ok stacked cards peek out by one stackStep each
                }
            }
        }
        .contextMenu { BlockMenu(block: block) }
        .id(block.uid)
        .transition(.opacity)
    }

    /// "Vinyl · discogs.com · saved 3 months ago · never opened".
    private var meta: String {
        let saved = "saved " + block.createdAt.formatted(.relative(presentation: .named))
        let opened = block.openedAt.map { "opened " + $0.formatted(.relative(presentation: .named)) } ?? "never opened"
        return [block.collection?.name, block.siteName.isEmpty ? nil : block.siteName, saved, opened]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Keep, Archive, Skip, Open, each showing its key.
private struct RediscoverBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            Button("Keep") { model.rediscoverKeep() }
                .buttonStyle(KitKeyButtonStyle(key: "K", prominent: true))
            Button("Archive") { model.rediscoverArchive() }
                .buttonStyle(KitKeyButtonStyle(key: "A"))
            Button("Skip") { model.rediscoverSkip() }
                .buttonStyle(KitKeyButtonStyle(key: "→"))
            if let block = model.rediscoverBlock, block.url != nil {
                Button("Open") { model.open(block) }
                    .buttonStyle(KitKeyButtonStyle(key: "↩"))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous).strokeBorder(Ink.hairline))
        .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rediscover this block")
    }
}
