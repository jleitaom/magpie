import MagpieKit
import SwiftData
import SwiftUI

/// The tags on a block, in the details panel (S-014): chips to filter by or remove, and a field
/// that suggests existing tags as you type. Return adds the tag; commas add several.
struct TagEditor: View {
    @Bindable var block: Block
    @Environment(AppModel.self) private var model
    /// Watched, so suggestions follow tags made, renamed or deleted elsewhere.
    @Query private var allTags: [Tag]
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        let mine = (block.tags ?? []).sorted { Tags.key($0.name) < Tags.key($1.name) }
        let names = allTags.map(\.name)
        let suggestions = typing ? Tags.suggestions(for: draft, from: names, excluding: mine.map(\.name), limit: 5) : []
        VStack(alignment: .leading, spacing: Space.sm) {
            KitFlow(spacing: Space.xs) {
                ForEach(mine, id: \.uid) { tag in
                    Button("#\(tag.name)") { model.scope = .tag(tag.uid); model.show(.gallery) }
                        .buttonStyle(KitTagChipStyle(color: UInt32(tag.colorHex), isSelected: model.scope == .tag(tag.uid)))
                        .help("Show every block tagged \(tag.name)")
                        .contextMenu {
                            Button("Remove from This Block") { model.removeTag(tag, from: block) }
                            Divider()
                            TagMenu(tag: tag)
                        }
                }
            }
            TextField(mine.isEmpty ? "Add a tag" : "Add another tag", text: $draft)
                .kitField()
                .focused($typing)
                .onSubmit(add)
                .onKeyPress(.tab) {
                    guard let first = suggestions.first else { return .ignored }
                    draft = first
                    return .handled
                }
            if !suggestions.isEmpty, !draft.isEmpty {
                KitFlow(spacing: Space.xs) {
                    ForEach(suggestions, id: \.self) { name in
                        let tag = model.tags.first { $0.name == name }
                        Button(name) {
                            model.addTags(name, to: block)
                            draft = ""
                        }
                        .buttonStyle(KitTagChipStyle(color: UInt32(tag?.colorHex ?? 0xA1A1A8)))
                    }
                }
                .accessibilityLabel("Suggested tags")
            }
        }
        .onChange(of: model.focusTagField) { _, ask in
            guard ask else { return }
            typing = true
            model.focusTagField = false
        }
        .onAppear {
            if model.focusTagField {
                typing = true
                model.focusTagField = false
            }
        }
    }

    /// Return: adds what's typed, or the first suggestion when what's typed is part of one.
    private func add() {
        let typed = Tags.clean(draft)
        guard !typed.isEmpty else { return }
        let names = model.tags.map(\.name)
        let exact = names.contains { Tags.key($0) == Tags.key(typed) }
        let pick = exact || typed.contains(",") ? typed
            : Tags.suggestions(for: typed, from: names, excluding: (block.tags ?? []).map(\.name), limit: 1).first ?? typed
        model.addTags(pick, to: block)
        draft = ""
        typing = true
    }
}

/// The right-click menu for a tag, wherever it shows (S-015).
struct TagMenu: View {
    let tag: Tag
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Show Blocks Tagged “\(tag.name)”") { model.scope = .tag(tag.uid); model.show(.gallery) }
        Divider()
        Button("Rename Tag…") { model.tagToRename = tag.uid }
        Menu("Color") {
            ForEach(CollectionColors.all, id: \.self) { hex in
                Toggle(colorName(hex), isOn: Binding(get: { tag.colorHex == hex }, set: { if $0 { model.recolor(tag, to: hex) } }))
            }
        }
        Divider()
        Button("Delete Tag…", role: .destructive) { model.tagToDelete = tag.uid }
    }

    private func colorName(_ hex: Int) -> String {
        switch hex {
        case 0x7FD9D3: "Teal"
        case 0xE8A27A: "Orange"
        case 0xE8CF8A: "Yellow"
        case 0xA8D5A2: "Green"
        case 0x8FB5E8: "Blue"
        case 0xC9A8E8: "Purple"
        case 0xE88FB0: "Pink"
        default: "Grey"
        }
    }
}

/// Every tag, in the Collections panel: click to show its blocks.
struct TagCloud: View {
    @Environment(AppModel.self) private var model
    /// Watched, so a tag deleted, renamed or recolored here updates the list right away (#4).
    @Query private var allTags: [Tag]

    var body: some View {
        let all = allTags.filter { !$0.isDeleted }.sorted { Tags.key($0.name) < Tags.key($1.name) }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Tags").kitType(.meta).foregroundStyle(Ink.secondary).padding(.horizontal, Space.xs)
                KitFlow(spacing: Space.xs) {
                    ForEach(all, id: \.uid) { tag in
                        Button("#\(tag.name)  \(tag.blocks?.count ?? 0)") {
                            model.scope = .tag(tag.uid)
                            model.show(.gallery)
                            model.showsCollections = false
                        }
                        .buttonStyle(KitTagChipStyle(color: UInt32(tag.colorHex), isSelected: model.scope == .tag(tag.uid)))
                        .contextMenu { TagMenu(tag: tag) }
                    }
                }
            }
        }
    }
}

extension View {
    /// The rename and delete prompts for tags. `when` picks which view shows them: the
    /// Collections panel while it's open, the window otherwise.
    func tagPrompts(when active: Bool) -> some View {
        modifier(TagPrompts(active: active))
    }
}

private struct TagPrompts: ViewModifier {
    let active: Bool
    @Environment(AppModel.self) private var model
    @State private var newName = ""

    func body(content: Content) -> some View {
        let renaming = model.tag(model.tagToRename)
        let deleting = model.tag(model.tagToDelete)
        content
            .alert("Rename “\(renaming?.name ?? "")”", isPresented: Binding(
                get: { active && renaming != nil }, set: { if !$0 { model.tagToRename = nil } }
            ), presenting: renaming) { tag in
                TextField("Name", text: $newName)
                    .onAppear { newName = tag.name }
                Button("Rename") { model.renameTag(tag, to: newName) }
                Button("Cancel", role: .cancel) { model.tagToRename = nil }
            } message: { _ in
                Text("Use another tag’s name to merge the two.")
            }
            .alert("Delete the tag “\(deleting?.name ?? "")”?", isPresented: Binding(
                get: { active && deleting != nil }, set: { if !$0 { model.tagToDelete = nil } }
            ), presenting: deleting) { tag in
                Button("Delete Tag", role: .destructive) { model.deleteTag(tag) }
                Button("Cancel", role: .cancel) { model.tagToDelete = nil }
            } message: { tag in
                let count = tag.blocks?.count ?? 0
                Text(count == 0 ? "No blocks have it." : "It comes off \(count == 1 ? "1 block" : "\(count) blocks"). The blocks stay.")
            }
    }
}
