import MagpieKit
import SwiftData
import SwiftUI

/// Sort Inbox (S-060): one Inbox block at a time, big, with a suggested collection.
/// M moves it there, D marks it done, → skips it, ⌫ deletes it (menu bar: Inbox).
struct SortInboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    /// Watched so the run follows the Inbox when something is saved or undone meanwhile.
    @Query private var blocks: [Block]

    var body: some View {
        let run = model.sortSession
        VStack(spacing: 0) {
            if let current = model.sortingBlock {
                progress(run)
                    .padding(.top, Space.md)
                SortCardStack(block: current, behind: min(run.upNext.count, 2))
                    .padding(.top, Space.xxl)
                Spacer(minLength: 0)
            } else if run.sorted > 0 {
                Spacer()
                InboxZero(run: run)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: Space.sm) {
                    Text("Nothing to sort").kitType(.display).foregroundStyle(Ink.text)
                    Text("New saves land in the Inbox. Come back after you’ve collected something.")
                        .kitType(.body).foregroundStyle(Ink.secondary)
                    Button("Back to Gallery") { model.show(.gallery) }
                        .buttonStyle(.kit(.secondary))
                        .padding(.top, Space.sm)
                }
                Spacer()
            }
        }
        .padding(.top, Metric.barHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.sortingBlock != nil {
                SortActionBar().padding(.bottom, Space.xxl)
            }
        }
        .onChange(of: blocks.filter { $0.status == .inbox }.map(\.uid)) { model.syncSorting() }
    }

    private func progress(_ run: SortSession) -> some View {
        VStack(spacing: Space.sm) {
            HStack {
                Text("Sorting your Inbox").kitType(.body).foregroundStyle(Ink.secondary)
                Spacer()
                let count = Text("\(run.sorted)").foregroundStyle(Ink.text).bold()
                Text("\(count) sorted · \(run.left) left").kitType(.body).foregroundStyle(Ink.secondary)
            }
            KitProgressBar(value: run.progress)
        }
        .frame(width: Metric.sortWidth)
        .accessibilityElement(children: .combine)
    }
}

/// The celebration after the last Inbox block is sorted (S-061).
private struct InboxZero: View {
    let run: SortSession
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: Space.lg) {
            ZStack {
                Circle().stroke(Ink.suggest, lineWidth: Metric.celebrationRing / 12)
                Circle()
                    .trim(from: 0, to: shown || reduceMotion ? 1 : 0)
                    .stroke(Ink.accentText, style: StrokeStyle(lineWidth: Metric.celebrationRing / 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                KitIconView(icon: .check, size: Metric.celebrationRing / 3).foregroundStyle(Ink.text)
            }
            .frame(width: Metric.celebrationRing, height: Metric.celebrationRing)
            .accessibilityHidden(true)
            Text("Inbox zero.").kitType(.display).foregroundStyle(Ink.text)
            Text("Your nest is tidy.").kitType(.body).foregroundStyle(Ink.secondary)
            HStack(spacing: Space.sm) {
                KitStatTile(value: run.sorted, label: "sorted")
                KitStatTile(value: run.kept, label: "kept")
                KitStatTile(value: run.done, label: "done")
                KitStatTile(value: run.deleted, label: "deleted")
            }
            .padding(.top, Space.xs)
            HStack(spacing: Space.sm) {
                Button("Back to Gallery") { model.show(.gallery) }
                    .buttonStyle(.kit(.secondary, large: true))
                Button("Rediscover \(Rediscover.perDay) old saves") { model.show(.rediscover) }
                    .buttonStyle(.kit(large: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Space.sm)
        }
        .frame(width: Metric.celebrationWidth)
        .onAppear { withAnimation(reduceMotion ? nil : Motion.progress) { shown = true } }
    }
}

/// The current block, big, with up to two cards stacked behind it.
private struct SortCardStack: View {
    let block: Block
    let behind: Int
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    var body: some View {
        if block.isGone { EmptyView() } else { live }
    }

    @ViewBuilder private var live: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radiusSortCard, style: .continuous)
        let content = CardLayout.content(for: block, width: Metric.sortWidth)
        let suggested = model.suggestion(for: block)
        Group {
            VStack(alignment: .leading, spacing: 0) {
                switch content.body {
                case .visual(let thumb):
                    ThumbView(thumb: thumb, badge: content.badge)
                        .frame(maxWidth: .infinity).frame(height: Metric.sortHero).clipped()
                case .place:
                    MapThumb().frame(maxWidth: .infinity).frame(height: Metric.sortHero).clipped()
                case .note, .checklist, .plain: EmptyView()
                }
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(meta).kitType(.meta).foregroundStyle(Ink.secondary)
                    SortTitle(block: block, title: content.title)
                    switch content.body {
                    case .note(let text):
                        Text(text).kitType(.body).foregroundStyle(Ink.text.opacity(0.85)).lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    case .checklist(let lines):
                        VStack(alignment: .leading, spacing: Metric.inlineGap) {
                            ForEach(lines.prefix(5)) { Toggle($0.text, isOn: .constant($0.done)).toggleStyle(KitCheckStyle()) }
                        }
                    default:
                        EmptyView()
                    }
                    MoveChips(suggested: suggested)
                        .padding(.top, Space.xs)
                }
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
            }
            .frame(width: Metric.sortWidth, alignment: .leading)
            .background(Ink.card(tint: block.tint))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Ink.hairline))
            .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
            // Up to two cards peeking out below: each one narrower and lower than the one in front.
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    ForEach((0..<behind).reversed(), id: \.self) { index in
                        let step = Metric.stackStep * CGFloat(index + 1)
                        shape.fill(index == 0 ? Ink.surface : Ink.control)
                            .overlay(shape.strokeBorder(Ink.hairline))
                            .padding(.horizontal, step * 2)
                            .offset(y: step) // grid: ok stacked cards peek out by one stackStep each
                    }
                }
            }
        }
        .frame(width: Metric.sortWidth)
        .contextMenu { BlockMenu(block: block) }
        .id(block.uid)
        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(block.kind.label): \(content.title)")
    }

    private var meta: String {
        let saved = block.createdAt.formatted(.relative(presentation: .named))
        return [block.kind.label, block.siteName, "saved \(saved)"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The card's title. Click it (or press R) to rename: the whole title is selected, Return saves,
/// Escape cancels. The sorting keys wait while you type.
private struct SortTitle: View {
    let block: Block
    let title: String
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        if model.isRenamingSortBlock {
            TextField("Title", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .kitType(.title)
                .foregroundStyle(Ink.text)
                .lineLimit(1...3)
                .focused($editing)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(RoundedRectangle(cornerRadius: Metric.radiusField).fill(Ink.control))
                .overlay(RoundedRectangle(cornerRadius: Metric.radiusField).strokeBorder(Ink.accentText, lineWidth: Metric.focusRing))
                .onSubmit(commit)
                .onExitCommand { model.isRenamingSortBlock = false }
                .task {
                    draft = block.title
                    await kitFocusAndSelectAll { editing = true; return editing }
                }
                .onChange(of: editing) { _, focused in
                    if !focused, model.isRenamingSortBlock { commit() }
                }
        } else {
            Text(title).kitType(.title).foregroundStyle(Ink.text)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .contentShape(.rect)
                .onTapGesture { model.isRenamingSortBlock = true }
                .help("Click to rename (R)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Rename")
        }
    }

    private func commit() {
        model.rename(block, to: draft)
        model.isRenamingSortBlock = false
    }
}

/// "Move to" chips: the suggested collection first, then the pinned ones, then "Other…" for the rest.
private struct MoveChips: View {
    let suggested: BlockCollection?
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    var body: some View {
        let pinned = model.pinnedCollections.filter { $0.uid != suggested?.uid }
        let others = model.collectionTree.map(\.collection).filter { candidate in
            candidate.uid != suggested?.uid && !pinned.contains { $0.uid == candidate.uid }
        }
        KitFlow(spacing: Space.sm) {
            Text("Move to").kitType(.meta).foregroundStyle(Ink.secondary)
                .frame(height: Metric.control)
            if let suggested {
                Button("Suggested: \(suggested.name)") { model.sortMove(to: suggested, undo: undo) }
                    .buttonStyle(KitChipStyle(isSelected: true))
                    .help("Move here (M)")
            }
            ForEach(pinned, id: \.uid) { target in
                Button(target.name) { model.sortMove(to: target, undo: undo) }.buttonStyle(KitChipStyle())
            }
            if !others.isEmpty {
                Menu {
                    ForEach(others, id: \.uid) { target in
                        Button(target.name) { model.sortMove(to: target, undo: undo) }
                    }
                } label: {
                    Text("Other…")
                }
                .menuStyle(.button)
                .buttonStyle(KitChipStyle())
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

/// The floating bar of actions, each showing its key.
private struct SortActionBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    var body: some View {
        let suggested = model.sortingBlock.flatMap(model.suggestion(for:))
        HStack(spacing: Space.sm) {
            Button(suggested.map { "Move to \($0.name)" } ?? "Move to suggested") { model.sortMove(to: suggested, undo: undo) }
                .buttonStyle(KitKeyButtonStyle(key: "M", prominent: true))
                .disabled(suggested == nil)
            Button("Done") { model.sortDone() }
                .buttonStyle(KitKeyButtonStyle(key: "D"))
            Button("Skip") { model.sortSkip() }
                .buttonStyle(KitKeyButtonStyle(key: "→"))
                .disabled(model.sortSession.left < 2)
            Button("Delete") { model.sortDelete(undo: undo) }
                .buttonStyle(KitKeyButtonStyle(key: "⌫"))
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous).strokeBorder(Ink.hairline))
        .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sort this block")
    }
}
