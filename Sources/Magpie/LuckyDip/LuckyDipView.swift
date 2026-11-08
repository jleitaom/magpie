import MagpieKit
import SwiftData
import SwiftUI

/// Lucky Dip (S-070–S-072): pick a pile and how much time you have, and Magpie picks one block.
/// Two re-spins a day, then you commit. Menu bar: Lucky Dip.
struct LuckyDipView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Watched so counts and the pick redraw when blocks change.
    @Query private var blocks: [Block]
    @Query private var days: [DayActivity]

    var body: some View {
        HStack(alignment: .top, spacing: Space.section) {
            PileColumn()
                .frame(width: Metric.dipSidebar)
            VStack(spacing: Space.lg) {
                stats
                stage
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.section + Space.sm)
        .padding(.top, Metric.barHeight + Space.xl)
        .padding(.bottom, Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var stats: some View {
        let pile = model.pileBlocks(model.dipPile)
        let time = LuckyDip.totalTime(pile.map(\.minutes))
        return HStack(spacing: Space.md) {
            DipStat(label: "On the \(model.dipPile.title) pile", value: "\(pile.count)", detail: time.isEmpty ? nil : time)
            DipStat(label: "Finished this week", value: "\(model.finishedThisWeek)")
            DipStat(label: "Daily dip streak", value: model.dipStreak == 1 ? "1 day" : "\(model.dipStreak) days", accent: true)
        }
    }

    @ViewBuilder
    private var stage: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radiusSortCard, style: .continuous)
        ZStack {
            if model.isShuffling {
                Shuffle(title: model.shuffleTitle)
            } else if let started = model.inProgressBlock {
                PickCard(block: started, inProgress: true)
            } else if let pick = model.dipPick {
                PickCard(block: pick, inProgress: false)
            } else {
                Idle(reduceMotion: reduceMotion)
            }
        }
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Ink.surface.opacity(0.6)))
        .overlay(shape.strokeBorder(Ink.hairline))
        .animation(reduceMotion ? nil : Motion.panel, value: model.isShuffling)
    }
}

/// The piles to choose from, and how much time you have.
private struct PileColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Pick a pile").kitType(.meta).foregroundStyle(Ink.secondary).padding(.horizontal, 2)
            ForEach(Pile.allCases) { pile in
                let blocks = model.pileBlocks(pile)
                let time = LuckyDip.totalTime(blocks.map(\.minutes))
                Button(pile.title) { model.dipPile = pile }
                    .buttonStyle(KitPileTileStyle(icon: pile.icon, detail: "\(blocks.count) waiting" + (time.isEmpty ? "" : " · \(time)"),
                                                  isSelected: model.dipPile == pile))
                    .disabled(model.isShuffling)
            }
            Text("How much time do you have?").kitType(.meta).foregroundStyle(Ink.secondary)
                .padding(.horizontal, 2).padding(.top, Space.md)
            KitFlow(spacing: Space.sm) {
                ForEach([nil, 10, 30, 60] as [Int?], id: \.self) { limit in
                    Button(label(limit)) { model.dipMaxMinutes = limit }
                        .buttonStyle(KitChipStyle(isSelected: model.dipMaxMinutes == limit))
                        .disabled(model.isShuffling)
                }
            }
        }
    }

    private func label(_ limit: Int?) -> String {
        switch limit {
        case nil: "Any length"
        case 60: "≤ 1 hour"
        case let minutes?: "≤ \(minutes) min"
        }
    }
}

private struct DipStat: View {
    let label: String
    let value: String
    var detail: String?
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).kitType(.meta).foregroundStyle(Ink.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Metric.inlineGap) {
                Text(value).kitType(.title).foregroundStyle(accent ? Ink.accentText : Ink.text)
                if let detail { Text("· \(detail)").kitType(.label).foregroundStyle(Ink.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(RoundedRectangle(cornerRadius: Metric.radiusCard - 2, style: .continuous).fill(Ink.surface))
        .accessibilityElement(children: .combine)
    }
}

/// Before the first spin: what Lucky Dip does, and the Randomize button.
private struct Idle: View {
    let reduceMotion: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.lg) {
            KitIconView(icon: .luckyDip, size: Metric.celebrationRing / 2).foregroundStyle(Ink.accentText)
            Text("Can’t decide? Let Magpie pick.").kitType(.display).foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
            let limit = model.dipMaxMinutes.map { " that fits in \(Badges.minutes($0))" } ?? ""
            let pile = model.pileBlocks(model.dipPile)
            let fitting = LuckyDip.fitting(pile.map { DipCandidate(id: $0.uid, minutes: $0.minutes, timesSkipped: $0.timesSkipped) },
                                           maxMinutes: model.dipMaxMinutes)
            Text(pile.isEmpty ? emptyPile : fitting.isEmpty
                 ? "Nothing on your \(model.dipPile.title) pile\(limit). Try more time, or another pile."
                 : "One random thing from your \(model.dipPile.title) pile\(limit). You get 2 re-spins a day. After that, you commit.")
                .kitType(.body).foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metric.celebrationWidth)
            if fitting.isEmpty {
                EmptyView()
            } else if model.canSpin {
                Button(model.spinsToday == 0 ? "Randomize" : "Spin again · \(model.respinsLeft) left today") {
                    model.spin(reduceMotion: reduceMotion)
                }
                .buttonStyle(.kit(large: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, Space.xs)
            } else {
                Text("No spins left today. Come back tomorrow.").kitType(.labelStrong).foregroundStyle(Ink.secondary)
            }
        }
    }
}

extension Idle {
    /// What goes on an empty pile, so you know how to fill it.
    fileprivate var emptyPile: String {
        let what = switch model.dipPile {
        case .read: "articles and essays"
        case .watch: "videos"
        case .listen: "music links (Discogs, Bandcamp, Spotify, Apple Music)"
        case .cook: "recipes"
        case .visit: "places from Apple Maps or Google Maps"
        }
        return "The \(model.dipPile.title) pile is empty. Save some \(what), or pick a pile for a block in its details."
    }
}

/// About a second of titles flicking past.
private struct Shuffle: View {
    let title: String

    var body: some View {
        VStack(spacing: Space.md) {
            Text("SHUFFLING…").kitType(.mono).foregroundStyle(Ink.accentText)
            Text(title).kitType(.title).foregroundStyle(Ink.text)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(maxWidth: Metric.dipPickMaxWidth * 0.8, minHeight: Metric.controlLarge * 2)
                .padding(Space.xl)
                .background(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous).fill(Ink.control))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shuffling")
    }
}

/// Today's pick, or the pick you started: picture on the left, what to do on the right.
private struct PickCard: View {
    let block: Block
    let inProgress: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if block.isGone { EmptyView() } else { live }
    }

    @ViewBuilder private var live: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radiusPanel, style: .continuous)
        let content = CardLayout.content(for: block, width: Metric.dipPickHero)
        let pile = block.pile ?? model.dipPile
        HStack(spacing: 0) {
            switch content.body {
            case .visual(let thumb): ThumbView(thumb: thumb).frame(width: Metric.dipPickHero).frame(maxHeight: .infinity).clipped()
            case .place: MapThumb().frame(width: Metric.dipPickHero).frame(maxHeight: .infinity)
            default: EmptyView()
            }
            VStack(alignment: .leading, spacing: Space.md) {
                Text(inProgress ? "IN PROGRESS" : "TODAY’S PICK")
                    .kitType(.mono).foregroundStyle(inProgress ? Ink.noteLabel : Ink.accentText)
                Text(content.title).kitType(.title).foregroundStyle(Ink.text)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(meta).kitType(.body).foregroundStyle(Ink.secondary)
                Spacer(minLength: Space.md)
                HStack(spacing: Space.sm) {
                    if inProgress {
                        Button("Mark as finished") { model.finishPick(block) }
                            .buttonStyle(.kit(large: true))
                            .keyboardShortcut(.defaultAction)
                        if block.url != nil {
                            Button("Open again") { model.open(block) }.buttonStyle(.kit(.secondary, large: true))
                        }
                    } else {
                        Button(pile.startVerb) { model.startPick(block) }
                            .buttonStyle(.kit(large: true))
                            .keyboardShortcut(.defaultAction)
                        Button(model.respinsLeft > 0 ? "Spin again · \(model.respinsLeft) left today" : "No spins left — commit!") {
                            model.spin(reduceMotion: reduceMotion)
                        }
                        .buttonStyle(.kit(.secondary, large: true))
                        .disabled(!model.canSpin)
                        Button("Not today") { model.notToday(block) }.buttonStyle(.kit(.ghost, large: true))
                    }
                }
            }
            .padding(Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Metric.dipPickMaxWidth, minHeight: Metric.dipPickMinHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(Ink.card(tint: block.tint))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.hairline))
        .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
        .contextMenu { BlockMenu(block: block) }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var meta: String {
        let saved = block.createdAt.formatted(.relative(presentation: .named))
        let length = block.minutes.map { Badges.minutes($0) }
        return [block.siteName, length, "saved \(saved)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
