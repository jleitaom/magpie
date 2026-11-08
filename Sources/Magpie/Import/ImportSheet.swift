import MagpieKit
import SwiftUI

/// The bookmarks import preview (S-042): the folder tree with counts and a check for each
/// folder, what the import will do, and Import.
struct ImportSheet: View {
    @State var plan: AppModel.BookmarkImport
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = plan.root.flattened()
        let result = BookmarkFile.plan(plan.root, folders: plan.chosen, includeLoose: plan.includeLoose, existing: model.existingURLs)
        let collections = Set(result.items.map { $0.folder.joined(separator: "/") }.filter { !$0.isEmpty }).count
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Import bookmarks").kitType(.title).foregroundStyle(Ink.text)
                Text("From \(plan.file). Folders become collections; tick the ones you want.")
                    .kitType(.body).foregroundStyle(Ink.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.folder.id) { row in
                        FolderRow(name: row.folder.name, count: row.folder.links.count, depth: row.depth,
                                  isOn: Binding(get: { plan.chosen.contains(row.folder.id) },
                                                set: { on in
                                                    if on { plan.chosen.insert(row.folder.id) } else { plan.chosen.remove(row.folder.id) }
                                                }))
                    }
                    if !plan.root.links.isEmpty {
                        FolderRow(name: "Not in a folder (to the Inbox)", count: plan.root.links.count, depth: 0, isOn: $plan.includeLoose)
                    }
                }
            }
            .frame(maxHeight: Metric.importListHeight)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.md) {
                Button(plan.chosen.count == rows.count ? "Select None" : "Select All") {
                    plan.chosen = plan.chosen.count == rows.count ? [] : Set(rows.map(\.folder.id))
                }
                .buttonStyle(.kit(.ghost))
                Spacer()
                Text(summary(result.items.count, collections: collections, duplicates: result.duplicates))
                    .kitType(.meta).foregroundStyle(Ink.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.bookmarkImport = nil }
                    .buttonStyle(.kit(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Import \(result.items.count)") { model.importBookmarks(plan) }
                    .buttonStyle(.kit())
                    .keyboardShortcut(.defaultAction)
                    .disabled(result.items.isEmpty)
            }
        }
        .padding(Space.xxl)
        .frame(width: Metric.importWidth)
        .background(Ink.surface)
        .kitScene()
    }

    private func summary(_ count: Int, collections: Int, duplicates: Int) -> String {
        var text = "\(count) \(count == 1 ? "bookmark" : "bookmarks")"
        if collections > 0 { text += " into \(collections) \(collections == 1 ? "collection" : "collections")" }
        if duplicates > 0 { text += " · \(duplicates) already saved" }
        return text
    }
}

private struct FolderRow: View {
    let name: String
    let count: Int
    let depth: Int
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            Toggle(name, isOn: $isOn).toggleStyle(KitCheckStyle(isTask: false))
            Spacer(minLength: Space.sm)
            Text("\(count)").kitType(.mono).foregroundStyle(Ink.secondary)
        }
        .padding(.leading, CGFloat(depth) * Metric.treeIndent)
        .frame(height: Metric.control)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}
