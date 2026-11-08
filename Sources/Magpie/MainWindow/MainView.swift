import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The one window: top bar, Gallery, details panel, and the drop target around it all.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Block.createdAt, order: .reverse) private var blocks: [Block]
    @Query(sort: \BlockCollection.sortIndex) private var collections: [BlockCollection]

    var body: some View {
        @Bindable var model = model
        let shown = model.blocks(in: model.scope, from: blocks)
        let selected = blocks.first { $0.uid == model.selection }

        ZStack(alignment: .top) {
            Ink.window
            if model.viewMode == .sortInbox {
                SortInboxView()
            } else if model.viewMode == .luckyDip {
                LuckyDipView()
            } else if shown.isEmpty {
                EmptyGallery(isLibraryEmpty: blocks.isEmpty, scopeName: scopeName)
            } else {
                GalleryView(blocks: shown, sortPrompt: model.scope == .inbox ? shown.count : 0)
            }
            TopBar(collections: collections, inboxCount: model.blocks(in: .inbox, from: blocks).count)
        }
        .overlay(alignment: .trailing) {
            if let selected, model.viewMode != .sortInbox {
                DetailsPanel(block: selected, collections: collections)
                    .padding(.top, Metric.barHeight)
                    .padding([.trailing, .bottom], Space.lg)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if model.viewMode == .gallery { BottomHint(showsHint: selected == nil) }
        }
        .overlay {
            if model.isDropTargeted {
                RoundedRectangle(cornerRadius: Metric.radiusPanel, style: .continuous)
                    .strokeBorder(Ink.accentText, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(Space.sm)
                    .overlay { Text("Drop to save").kitType(.heading).foregroundStyle(Ink.accentText) }
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.panel, value: model.selection)
        .onDrop(of: DropReader.types, isTargeted: $model.isDropTargeted) { providers in
            DropReader.read(providers, into: model)
            return true
        }
        .ignoresSafeArea()
        .collectionDeleteAlert(when: !model.showsCollections)
        .tagPrompts(when: !model.showsCollections)
        .task {
            model.start()
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var scopeName: String {
        switch model.scope {
        case .all: "Magpie"
        case .inbox: "your Inbox"
        case .collection(let uid): collections.first { $0.uid == uid }?.name ?? "this collection"
        case .tag(let uid): model.tag(uid).map { "#\($0.name)" } ?? "this tag"
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    let collections: [BlockCollection]
    let inboxCount: Int
    @Environment(AppModel.self) private var model
    /// The right-hand controls' width, mirrored on the left so the pill stays centered.
    private let sideWidth: CGFloat = 212

    var body: some View {
        @Bindable var model = model
        HStack(spacing: Space.md) {
            HStack {
                Button(model.streakDays == 0 ? "Start a streak" : "\(model.streakDays)-day streak") { model.startSorting() }
                    .buttonStyle(KitStreakPillStyle(days: model.streakDays))
                    .help("Days in a row you reached Inbox zero. Click to sort your Inbox (⌃⌘3).")
                    .accessibilityLabel("\(model.streakDays)-day Inbox zero streak. Sort Inbox")
                Spacer(minLength: 0)
            }
            .padding(.leading, Metric.streakInset - Space.lg)
            .frame(width: sideWidth)
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                pill(maxPins: 5)
                pill(maxPins: 3)
                pill(maxPins: 1)
                pill(maxPins: 0)
            }
            .popover(isPresented: $model.showsCollections, arrowEdge: .bottom) {
                CollectionsPopover()
                    .environment(model)
                    .onDisappear { model.renamingCollection = nil }
                    .kitPopover()
            }
            Spacer(minLength: 0)
            RightControls().frame(width: sideWidth, alignment: .trailing)
        }
        .padding(.horizontal, Space.lg)
        .frame(height: Metric.barHeight)
    }

    private func pill(maxPins: Int) -> some View {
        let pinned = Array(collections.filter(\.isPinned).sorted { $0.pinIndex < $1.pinIndex }.prefix(maxPins))
        var shownIDs = Set(pinned.map(\.uid))
        var extra: BlockCollection?
        if case .collection(let uid) = model.scope, !shownIDs.contains(uid) {
            extra = collections.first { $0.uid == uid }
            if let extra { shownIDs.insert(extra.uid) }
        }
        let hidden = collections.count - shownIDs.count
        return KitPillBar {
            tab("All", scope: .all)
            tab("Inbox", scope: .inbox, count: inboxCount)
            ForEach(pinned) { collectionTab($0) }
            if let extra { collectionTab(extra) }
            if let tag = model.openTag {
                tab("# \(tag.name)", scope: .tag(tag.uid))
                    .contextMenu { TagMenu(tag: tag) }
            }
            KitBarDivider()
            Button { model.showsCollections.toggle() } label: {
                HStack(spacing: Metric.inlineGap) {
                    Text(hidden > 0 ? "\(hidden) more" : "Collections")
                    KitIconView(icon: .chevronDown, size: 10)
                }
            }
            .buttonStyle(KitTabStyle(isSelected: false))
            .help("All collections (⌘K)")
        }
    }

    @ViewBuilder
    private func collectionTab(_ target: BlockCollection) -> some View {
        if model.renamingCollection == target.uid, !model.showsCollections {
            KitTabField(initial: target.name,
                        onCommit: { model.rename(target, to: $0) },
                        onCancel: { model.renamingCollection = nil })
        } else {
            tab(target.name, scope: .collection(target.uid))
                .contextMenu { CollectionMenu(target: target) }
        }
    }

    private func tab(_ title: String, scope: Scope, count: Int? = nil) -> some View {
        Button(title) {
            model.scope = scope
            if model.viewMode != .gallery { model.show(.gallery) }
            model.selection = nil
        }
        .buttonStyle(KitTabStyle(isSelected: model.scope == scope, count: count))
    }
}

private struct RightControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: Space.sm) {
            KitSegmentTrack {
                ForEach(ViewMode.allCases) { mode in
                    Button { model.show(mode) } label: { KitIconView(icon: mode.icon) }
                        .buttonStyle(KitSegmentStyle(isSelected: model.viewMode == mode))
                        .disabled(!mode.isAvailable)
                        .help(mode.isAvailable ? "\(mode.title) (\(mode.shortcutLabel))" : "\(mode.title) — coming soon")
                        .accessibilityLabel(mode.title)
                }
            }
            Button { model.showsNewMenu.toggle() } label: { KitIconView(icon: .add) }
                .buttonStyle(KitRoundButtonStyle())
                .help("New block")
                .accessibilityLabel("New block")
                .popover(isPresented: $model.showsNewMenu, arrowEdge: .bottom) {
                    NewBlockMenu { model.showsNewMenu = false }.environment(model).kitPopover()
                }
        }
    }
}

private struct NewBlockMenu: View {
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New block").kitType(.meta).foregroundStyle(Ink.secondary)
                .padding(.horizontal, Metric.rowInset).padding(.vertical, Space.sm)
            row("Note", swatch: Ink.noteLabel, shortcut: "⌘N") { model.addNote() }
            row("Checklist", swatch: Ink.accentText, shortcut: "⇧⌘N") { model.addChecklist() }
            row("Paste from clipboard", swatch: Ink.tertiary, shortcut: "⇧⌘V") { model.paste() }
            Text("Or drop links, images, files and text anywhere in the window.")
                .kitType(.meta).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Metric.rowInset)
        }
        .padding(Metric.popoverPadding)
        .frame(width: Metric.popoverWidth)
    }

    private func row(_ title: String, swatch: Color, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            dismiss()
            action()
        }
        .buttonStyle(KitMenuRowStyle(swatch: swatch, shortcut: shortcut))
    }
}

// MARK: - Bottom hint and messages

private struct BottomHint: View {
    let showsHint: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let toast = model.toast {
                Text(toast)
                    .kitType(.label)
                    .foregroundStyle(Ink.onChosen)
                    .padding(.horizontal, Space.lg)
                    .frame(height: Metric.control + Space.sm)
                    .background(Capsule().fill(Ink.chosen))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            } else if showsHint {
                HStack(spacing: Space.md) {
                    Text("Drop anything to make a block").kitType(.label).foregroundStyle(Ink.text)
                    Text("⇧⌘V").kitType(.mono).foregroundStyle(Ink.secondary)
                        .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
                        .background(RoundedRectangle(cornerRadius: Metric.radiusBadge).fill(Ink.control))
                }
                .padding(.leading, Space.lg).padding(.trailing, Space.sm)
                .frame(height: Metric.control + Space.sm)
                .background(Capsule().fill(Ink.surface))
                .overlay(Capsule().strokeBorder(Ink.hairline))
                .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
            }
        }
        .padding(.bottom, Space.lg + Space.xs)
        .animation(Motion.hover, value: model.toast)
    }
}

private struct EmptyGallery: View {
    let isLibraryEmpty: Bool
    let scopeName: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.md) {
            Text(isLibraryEmpty ? "Drop anything here." : "Nothing in \(scopeName) yet.")
                .kitType(.display).foregroundStyle(Ink.text)
            Text(isLibraryEmpty
                 ? "Links, images, files or text — drag them into this window, or copy a link and press ⇧⌘V."
                 : "Drop something here, or move blocks in from the details panel.")
                .kitType(.body).foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: Space.sm) {
                Button("Paste from clipboard") { model.paste() }.buttonStyle(.kit())
                Button("New note") { model.addNote() }.buttonStyle(.kit(.secondary))
            }
            .padding(.top, Space.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dropping things in

/// Reads dropped items into plain values and saves them. Each callback is `@Sendable`,
/// so it never runs main-actor code on the item provider's background queue.
enum DropReader {
    static let types: [UTType] = [.fileURL, .url, .image, .plainText]

    static func read(_ providers: [NSItemProvider], into model: AppModel) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.save(.file(url)) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.save(url.isFileURL ? .file(url) : .web(url)) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable data, _ in
                    guard let data else { return }
                    Task { @MainActor in model.save(.image(data, name: nil)) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { @Sendable text, _ in
                    guard let text else { return }
                    Task { @MainActor in model.save(.text(text)) }
                }
            }
        }
    }
}
