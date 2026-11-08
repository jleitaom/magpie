import MagpieKit
import SwiftUI

/// The panel that slides in from the right with a block's details. Edits save as you type.
struct DetailsPanel: View {
    @Bindable var block: Block
    let collections: [BlockCollection]
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if block.isGone { EmptyView() } else { live }
    }

    @ViewBuilder private var live: some View {
        KitPanel {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let data = block.thumbnail, let image = ThumbnailCache.image(for: block.uid, data: data) {
                        ThumbView(thumb: .image(image))
                            .frame(height: min(Metric.panelWidth / max(block.thumbnailAspect, 0.6), 260))
                            .clipped()
                    } else if block.kind == .place {
                        MapThumb().frame(height: 160)
                    }
                    VStack(alignment: .leading, spacing: Space.lg) {
                        header
                        if block.timesSkipped >= LuckyDip.skipsBeforeAsking {
                            stillWant
                        }
                        content
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Tags").kitType(.meta).foregroundStyle(Ink.secondary)
                            TagEditor(block: block)
                        }
                        facts
                    }
                    .padding(Space.xl)
                }
            }
            .scrollIndicators(.never)
            .safeAreaInset(edge: .bottom) { actions }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: block.title) { model.save() }
        .onChange(of: block.note) { model.save() }
        .onChange(of: block.bodyText) { model.save() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(block.kind.label.uppercased()).kitType(.kind)
                    .foregroundStyle(block.kind == .note ? Ink.noteLabel : Ink.secondary)
                TextField("Title", text: $block.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .kitType(.heading)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1...4)
            }
            Spacer(minLength: 0)
            Button { model.selection = nil } label: { KitIconView(icon: .close, size: 11) }
                .buttonStyle(.kit(.secondary))
                .help("Close (Esc)")
                .accessibilityLabel("Close details")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let url = block.url {
            Button { model.open(block) } label: {
                Text(url.isFileURL ? url.path : url.absoluteString)
                    .kitType(.meta)
                    .foregroundStyle(Ink.accentText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Open")
            .contextMenu {
                Button("Open") { model.open(block) }
                Button("Copy Link") { model.copy(block) }
            }
        }
        switch block.kind {
        case .note:
            TextField("Write something…", text: $block.bodyText, axis: .vertical)
                .lineLimit(6...20)
                .kitField()
                .onChange(of: block.bodyText) { _, text in
                    let first = Titles.firstLine(text)
                    if block.title == "New note" || block.title.isEmpty, !first.isEmpty { block.title = first }
                }
        case .checklist:
            ChecklistEditor(block: block)
        default:
            VStack(alignment: .leading, spacing: Metric.inlineGap) {
                Text("Note").kitType(.meta).foregroundStyle(Ink.secondary)
                TextField("Why did you save this?", text: $block.note, axis: .vertical)
                    .lineLimit(2...8)
                    .kitField()
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.sm) {
            GridRow {
                Text("Collection").kitType(.meta).foregroundStyle(Ink.secondary)
                Menu(block.collection?.name ?? "Inbox") {
                    Button("Inbox") { model.move(block, to: nil, undo: undoManager) }
                    Divider()
                    ForEach(collections) { target in
                        Button(target.name) { model.move(block, to: target, undo: undoManager) }
                    }
                    Divider()
                    Button("Manage Collections…") { model.showsCollections = true }
                }
                .menuStyle(.button)
                .buttonStyle(.kit(.secondary))
                .fixedSize()
            }
            GridRow {
                Text("Pile").kitType(.meta).foregroundStyle(Ink.secondary)
                Menu(pileLabel) {
                    Button("Automatic") { model.setPile(block, to: nil) }
                    Divider()
                    ForEach(Pile.allCases) { pile in
                        Button(pile.title) { model.setPile(block, to: pile) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.kit(.secondary))
                .fixedSize()
                .help("The Lucky Dip pile it’s on. Automatic works it out from the kind.")
            }
            if let expires = block.expiresAt, block.status != .archived {
                GridRow {
                    Text("Expires").kitType(.meta).foregroundStyle(Ink.secondary)
                    HStack(spacing: Space.sm) {
                        Text(expires.formatted(.relative(presentation: .named)))
                            .kitType(.meta).foregroundStyle(Expiry.label(expires, now: .now) == nil ? Ink.text : Ink.noteLabel)
                        Button("Keep") { model.keep(block) }
                            .buttonStyle(.kit(.secondary))
                            .help("Stop this block from expiring")
                    }
                }
            }
            if let expired = block.expiredAt {
                GridRow {
                    Text("Expired").kitType(.meta).foregroundStyle(Ink.secondary)
                    Text(expired.formatted(.dateTime.day().month().year())).kitType(.meta).foregroundStyle(Ink.text)
                }
            }
            GridRow {
                Text("Saved").kitType(.meta).foregroundStyle(Ink.secondary)
                Text(block.createdAt.formatted(.dateTime.day().month().hour().minute()))
                    .kitType(.meta).foregroundStyle(Ink.text)
            }
            if let hex = block.tint {
                GridRow {
                    Text("Color").kitType(.meta).foregroundStyle(Ink.secondary)
                    HStack(spacing: Space.sm) {
                        RoundedRectangle(cornerRadius: Metric.radiusCheck).fill(Ink.swatch(hex))
                            .frame(width: Metric.check, height: Metric.check)
                        Text("from the image").kitType(.meta).foregroundStyle(Ink.text)
                    }
                }
            }
        }
    }

    /// "Automatic · Read", "Cook" (chosen by hand), or "Automatic · none".
    private var pileLabel: String {
        if let chosen = block.pileOverride { return chosen.title }
        return "Automatic · " + (block.pile?.title ?? "none")
    }

    /// After 3 "Not today"s in Lucky Dip.
    private var stillWant: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Still want this?").kitType(.labelStrong).foregroundStyle(Ink.text)
            Text("You passed on it \(block.timesSkipped) times in Lucky Dip.").kitType(.meta).foregroundStyle(Ink.secondary)
            HStack(spacing: Space.sm) {
                Button("Keep it") { model.keepWanting(block) }.buttonStyle(.kit())
                Button("Delete") { model.delete([block.uid], undo: undoManager) }.buttonStyle(.kit(.secondary))
            }
            .padding(.top, Space.xs)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous).fill(Ink.suggest))
    }

    private var actions: some View {
        HStack(spacing: Space.sm) {
            Button("Delete") { model.delete([block.uid], undo: undoManager) }
                .buttonStyle(.kit(.ghost))
            if block.status == .archived {
                Button("Unarchive") { model.unarchive(block) }.buttonStyle(.kit(.secondary))
            } else {
                Button("Archive") { model.archive(block, undo: undoManager) }.buttonStyle(.kit(.secondary))
            }
            Spacer()
            if block.url != nil {
                Button("Open") { model.open(block) }
                    .buttonStyle(.kit())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.lg)
        .background(Ink.surface)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}

/// Edits a checklist's items: tick, rename, add, remove.
private struct ChecklistEditor: View {
    @Bindable var block: Block
    @Environment(AppModel.self) private var model
    @FocusState private var focused: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(block.checklist) { item in
                HStack(spacing: Space.sm) {
                    Toggle("", isOn: binding(item.id, \.done)).toggleStyle(KitCheckStyle()).labelsHidden()
                    TextField("Item", text: binding(item.id, \.text))
                        .textFieldStyle(.plain)
                        .kitType(.body)
                        .foregroundStyle(item.done ? Ink.secondary : Ink.text)
                        .focused($focused, equals: item.id)
                        .onSubmit { addItem() }
                    Button { remove(item.id) } label: { KitIconView(icon: .close, size: 9) }
                        .buttonStyle(.kit(.ghost))
                        .accessibilityLabel("Remove item")
                }
            }
            Button("Add item") { addItem() }.buttonStyle(.kit(.secondary))
        }
    }

    private func binding<T>(_ id: UUID, _ path: WritableKeyPath<ChecklistItem, T>) -> Binding<T> {
        Binding {
            block.checklist.first { $0.id == id }?[keyPath: path] ?? ChecklistItem(text: "")[keyPath: path]
        } set: { value in
            var items = block.checklist
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index][keyPath: path] = value
            block.checklist = items
            model.save()
        }
    }

    private func addItem() {
        let item = ChecklistItem(text: "")
        block.checklist.append(item)
        model.save()
        focused = item.id
    }

    private func remove(_ id: UUID) {
        block.checklist.removeAll { $0.id == id }
        model.save()
    }
}
