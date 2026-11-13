import MagpieKit
import SwiftUI
import UniformTypeIdentifiers

/// Every collection as an indented tree: open one, pin it to the top bar (up to 5), drag it
/// to reorder or nest it, rename or delete it from its context menu, or make a new one.
struct CollectionsPopover: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var newName = ""
    @State private var dragging: UUID?
    @State private var drop: (target: UUID, placement: TreePlacement)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Find a collection", text: $search).kitField()
                // Off while a name is being edited, so the panel can't hand it the focus.
                .disabled(model.renamingCollection != nil)
            HStack {
                Text("All collections").kitType(.meta).foregroundStyle(Ink.secondary)
                Spacer()
                Text("Drag to reorder or nest · pin up to \(Pins.limit)").kitType(.meta).foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Space.xs)
            let rows = filtered
            if rows.isEmpty {
                Text(model.collections.isEmpty ? "No collections yet. Make your first one below." : "No collection matches “\(search)”.")
                    .kitType(.body).foregroundStyle(Ink.secondary)
                    .padding(.vertical, Space.md).padding(.horizontal, Space.xs)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.collection.uid) { row in
                            CollectionRow(target: row.collection, depth: isSearching ? 0 : row.depth,
                                          dropPlacement: drop?.target == row.collection.uid ? drop?.placement : nil)
                                .onDrag {
                                    dragging = row.collection.uid
                                    return NSItemProvider(object: row.collection.uid.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: RowDrop(target: row.collection.uid, model: model,
                                                                       dragging: $dragging, drop: $drop))
                        }
                    }
                }
                .frame(maxHeight: Metric.collectionsMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            TagCloud()
                .padding(.top, Space.xs)
            Button("Archive  \(model.archiveCount)") { open(.archive) }
                .buttonStyle(KitChipStyle(isSelected: model.scope == .archive))
                .help("Blocks you archived (⌃⌘0)")
            HStack(spacing: Space.sm) {
                TextField("New collection", text: $newName).kitField().onSubmit(create)
                Button("Add", action: create).buttonStyle(.kit()).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.md)
        .frame(width: Metric.collectionsWidth)
        .collectionDeleteAlert(when: true)
        .tagPrompts(when: true)
    }

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filtered: [(collection: BlockCollection, depth: Int)] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let tree = model.collectionTree
        return query.isEmpty ? tree : tree.filter { $0.collection.name.localizedStandardContains(query) }
    }

    private func open(_ place: Scope) {
        model.scope = place
        model.show(.gallery)
        model.showsCollections = false
    }

    private func create() {
        guard let created = model.createCollection(named: newName) else { return }
        newName = ""
        model.scope = .collection(created.uid)
        model.showsCollections = false
    }
}

/// One collection in the tree. Its name turns into a field while it's being renamed.
private struct CollectionRow: View {
    let target: BlockCollection
    let depth: Int
    let dropPlacement: TreePlacement?
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        let isOpen = model.scope == .collection(target.uid)
        let isRenaming = model.renamingCollection == target.uid
        HStack(spacing: 0) {
            if isRenaming {
                // Outside the row's button: a field inside a disabled button can't take focus.
                HStack(spacing: Space.sm) {
                    swatch
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain)
                        .kitType(.label).foregroundStyle(Ink.text)
                        .focused($editing)
                        .onSubmit { model.rename(target, to: draft) }
                        .onExitCommand { model.renamingCollection = nil }
                        .onChange(of: editing) { _, focused in
                            // Clicking away saves a changed name. A focus change while the panel
                            // is still opening (name unchanged) keeps the field open.
                            if !focused, model.renamingCollection == target.uid, draft != target.name {
                                model.rename(target, to: draft)
                            }
                        }
                }
                .padding(.leading, Metric.rowInset + CGFloat(depth) * Metric.treeIndent)
                .frame(height: Metric.menuRowHeight)
                .task {
                    draft = target.name
                    // The panel may still be opening and hand focus elsewhere: keep asking, then select the name.
                    await kitFocusAndSelectAll { editing = true; return editing }
                }
            } else {
                Button {
                    model.scope = .collection(target.uid)
                    model.selection = nil
                    model.showsCollections = false
                } label: {
                    HStack(spacing: Space.sm) {
                        swatch
                        Text(target.name).kitType(.label).foregroundStyle(Ink.text).lineLimit(1)
                        Text("\(target.blocks?.count ?? 0)").kitType(.meta).foregroundStyle(Ink.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, Metric.rowInset + CGFloat(depth) * Metric.treeIndent)
                    .frame(height: Metric.menuRowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Button { model.togglePin(target) } label: {
                KitIconView(icon: .pin, size: Metric.iconSmall, filled: target.isPinned)
                    .foregroundStyle(target.isPinned ? Ink.accentText : Ink.tertiary)
                    .frame(width: Metric.control, height: Metric.control)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(target.isPinned ? "Unpin from the top bar" : "Pin to the top bar")
            .accessibilityLabel(target.isPinned ? "Unpin \(target.name)" : "Pin \(target.name)")
        }
        .background(RoundedRectangle(cornerRadius: Metric.menuRowRadius).fill(isOpen || dropPlacement == .inside(target.uid) ? Ink.hover : .clear))
        .overlay {
            if dropPlacement == .inside(target.uid) {
                RoundedRectangle(cornerRadius: Metric.menuRowRadius).strokeBorder(Ink.accentText, lineWidth: Metric.dropLine)
            }
        }
        .overlay(alignment: dropPlacement == .before(target.uid) ? .top : .bottom) {
            if dropPlacement == .before(target.uid) || dropPlacement == .after(target.uid) {
                Capsule().fill(Ink.accentText).frame(height: Metric.dropLine)
                    .padding(.leading, Metric.rowInset + CGFloat(depth) * Metric.treeIndent)
            }
        }
        .contextMenu { CollectionMenu(target: target, inPanel: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(target.name), \(target.blocks?.count ?? 0) blocks\(depth > 0 ? ", nested" : "")")
    }
}

extension CollectionRow {
    fileprivate var swatch: some View {
        RoundedRectangle(cornerRadius: Metric.swatchRadius).fill(Ink.swatch(UInt32(target.colorHex)))
            .frame(width: Metric.swatch, height: Metric.swatch)
    }
}

/// Where a dragged row would land: the top quarter puts it before the row, the bottom
/// quarter after it, and the middle inside it.
private struct RowDrop: DropDelegate {
    let target: UUID
    let model: AppModel
    @Binding var dragging: UUID?
    @Binding var drop: (target: UUID, placement: TreePlacement)?

    private func placement(_ info: DropInfo) -> TreePlacement? {
        guard let dragging, dragging != target else { return nil }
        let y = info.location.y
        let placement: TreePlacement = y < Metric.menuRowHeight * 0.25 ? .before(target)
            : y > Metric.menuRowHeight * 0.75 ? .after(target) : .inside(target)
        let nodes = model.collections.map(\.node)
        return CollectionTree.move(dragging, to: placement, in: nodes) == nil ? nil : placement
    }

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let placement = placement(info) {
            drop = (target, placement)
            return DropProposal(operation: .move)
        }
        if drop?.target == target { drop = nil }
        return DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        if drop?.target == target { drop = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            drop = nil
            dragging = nil
        }
        guard let placement = placement(info), let moving = model.collection(dragging) else { return false }
        return model.place(moving, placement)
    }
}

/// The context menu for a collection, in the Collections panel and on its top bar tab.
struct CollectionMenu: View {
    let target: BlockCollection
    /// From the Collections panel the name is edited in its row; from a top bar tab, in the tab.
    var inPanel = false
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Rename…") {
            model.renamingCollection = target.uid
            if inPanel { model.showsCollections = true }
        }
        Menu("Move Into") {
            if target.parent != nil {
                Button("Top Level") { model.place(target, .topLevel) }
                Divider()
            }
            ForEach(model.possibleParents(for: target), id: \.uid) { parent in
                Button(parent.name) { model.place(target, .inside(parent.uid)) }
            }
        }
        Button("Move Up") { model.step(target, up: true) }
            .disabled(CollectionTree.step(target.uid, up: true, in: model.collections.map(\.node)) == nil)
        Button("Move Down") { model.step(target, up: false) }
            .disabled(CollectionTree.step(target.uid, up: false, in: model.collections.map(\.node)) == nil)
        Divider()
        Button(target.isPinned ? "Unpin from Top Bar" : "Pin to Top Bar") { model.togglePin(target) }
        Divider()
        Button("Delete Collection…", role: .destructive) { model.collectionToDelete = target.uid }
    }
}

extension View {
    /// The confirmation before a collection is deleted. It says how many blocks go back
    /// to the Inbox. `when` picks which view shows it: the Collections panel while it's
    /// open, the window otherwise.
    func collectionDeleteAlert(when active: Bool) -> some View {
        modifier(CollectionDeleteAlert(active: active))
    }
}

private struct CollectionDeleteAlert: ViewModifier {
    let active: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let target = model.collection(model.collectionToDelete)
        content.alert(
            "Delete “\(target?.name ?? "")”?",
            isPresented: Binding(get: { active && target != nil }, set: { if !$0 { model.collectionToDelete = nil } }),
            presenting: target
        ) { target in
            Button("Delete", role: .destructive) { model.deleteCollection(target) }
            Button("Cancel", role: .cancel) { model.collectionToDelete = nil }
        } message: { target in
            Text(model.deleteMessage(for: target))
        }
    }
}
