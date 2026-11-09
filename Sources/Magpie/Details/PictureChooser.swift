import AppKit
import MagpieKit
import SwiftUI

/// Choose Picture… (#2): the pictures on a block's page, to pick the one its card shows.
/// The current picture comes first; click another to use it. Escape cancels.
struct PictureChooser: View {
    let choice: PictureChoice
    @Environment(AppModel.self) private var model

    var body: some View {
        // The model's state, live: the pictures arrive after the sheet opens.
        let choice = model.pictureChoice ?? self.choice
        let block = model.block(choice.uid)
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Choose a picture").kitType(.title).foregroundStyle(Ink.text)
                Text(block.map { "From the page of “\($0.title)”." } ?? "")
                    .kitType(.body).foregroundStyle(Ink.secondary).lineLimit(2)
            }
            content(choice, block)
            HStack {
                Spacer()
                Button("Cancel") { model.pictureChoice = nil }
                    .buttonStyle(.kit(.secondary))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: Metric.pictureChooserWidth)
        .background(Ink.surface)
        .kitScene()
    }

    @ViewBuilder
    private func content(_ choice: PictureChoice, _ block: Block?) -> some View {
        if let choices = choice.choices, let block {
            let current = block.thumbnail
            let others = choices.filter { $0.jpeg != current }
            if others.isEmpty {
                Text("This page has no other pictures to choose from.")
                    .kitType(.body).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, minHeight: Metric.pictureTile.height)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Metric.pictureTile.width), spacing: Space.md), count: 3),
                              alignment: .leading, spacing: Space.md) {
                        if let current, let image = NSImage(data: current) {
                            Button {} label: { Picture(image: image) }
                                .buttonStyle(KitPictureTileStyle(isSelected: true))
                                .help("The picture it has now")
                        }
                        ForEach(Array(others.enumerated()), id: \.offset) { _, option in
                            if let image = NSImage(data: option.jpeg) {
                                Button { model.setPicture(option, for: block) } label: { Picture(image: image) }
                                    .buttonStyle(KitPictureTileStyle())
                                    .help("Use this picture")
                            }
                        }
                    }
                }
                .frame(maxHeight: Metric.importListHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text("Looking for pictures on the page…").kitType(.body).foregroundStyle(Ink.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: Metric.pictureTile.height)
        }
    }
}

private struct Picture: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image).resizable().scaledToFill()
            .frame(width: Metric.pictureTile.width, height: Metric.pictureTile.height)
            .background(Ink.control)
    }
}
