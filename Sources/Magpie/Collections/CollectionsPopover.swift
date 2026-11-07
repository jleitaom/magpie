import MagpieKit
import SwiftUI

/// Every collection: open one, pin it to the top bar (up to 5), or make a new one.
struct CollectionsPopover: View {
    let collections: [BlockCollection]
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Find a collection", text: $search).kitField()
            HStack {
                Text("All collections").kitType(.meta).foregroundStyle(Ink.secondary)
                Spacer()
                Text("Pin up to \(Pins.limit) to the top bar").kitType(.meta).foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Space.xs)
            if filtered.isEmpty {
                Text(collections.isEmpty ? "No collections yet. Make your first one below." : "No collection matches “\(search)”.")
                    .kitType(.body).foregroundStyle(Ink.secondary)
                    .padding(.vertical, Space.md).padding(.horizontal, Space.xs)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.xs), GridItem(.flexible())], spacing: Space.xs) {
                        ForEach(filtered) { row($0) }
                    }
                }
                .frame(maxHeight: 320)
            }
            HStack(spacing: Space.sm) {
                TextField("New collection", text: $newName).kitField().onSubmit(create)
                Button("Add", action: create).buttonStyle(.kit()).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.md)
        .frame(width: 460)
    }

    private var filtered: [BlockCollection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? collections : collections.filter { $0.name.localizedStandardContains(query) }
    }

    private func row(_ target: BlockCollection) -> some View {
        let isOpen = model.scope == .collection(target.uid)
        return HStack(spacing: 0) {
            Button {
                model.scope = .collection(target.uid)
                model.selection = nil
                model.showsCollections = false
            } label: {
                HStack(spacing: Space.sm) {
                    RoundedRectangle(cornerRadius: Metric.swatchRadius).fill(Ink.swatch(UInt32(target.colorHex)))
                        .frame(width: Metric.swatch, height: Metric.swatch)
                    Text(target.name).kitType(.label).foregroundStyle(Ink.text).lineLimit(1)
                    Text("\(target.blocks?.count ?? 0)").kitType(.meta).foregroundStyle(Ink.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Metric.rowInset)
                .frame(height: Metric.menuRowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button { model.togglePin(target) } label: {
                KitIconView(icon: .pin, size: 12, filled: target.isPinned)
                    .foregroundStyle(target.isPinned ? Ink.accentText : Ink.tertiary)
                    .frame(width: Metric.control, height: Metric.control)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(target.isPinned ? "Unpin from the top bar" : "Pin to the top bar")
            .accessibilityLabel(target.isPinned ? "Unpin \(target.name)" : "Pin \(target.name)")
        }
        .background(RoundedRectangle(cornerRadius: Metric.menuRowRadius).fill(isOpen ? Ink.hover : .clear))
        .contextMenu {
            Button("Delete Collection", role: .destructive) { model.deleteCollection(target) }
        }
    }

    private func create() {
        guard let created = model.createCollection(named: newName) else { return }
        newName = ""
        model.scope = .collection(created.uid)
        model.showsCollections = false
    }
}
