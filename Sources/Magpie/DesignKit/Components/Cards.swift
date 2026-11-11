import MagpieKit
import AppKit
import SwiftUI

/// What a card shows, built from a Block (CardLayout in GalleryView.swift).
struct CardContent: Identifiable {
    enum Body {
        case visual(CardThumb)
        case note(String)
        case checklist([ChecklistLine])
        case place
        /// No picture (a link whose page had none): title and site only.
        case plain
    }

    struct ChecklistLine: Identifiable {
        let id = UUID()
        var text: String
        var done: Bool
    }

    var id = UUID()
    var body: Body
    var kindLabel: String
    var title: String
    var site: String
    var badge: String?
    /// The image's main color, for the card background (nil: plain surface).
    var tint: UInt32?
    /// Thumbnail height in the Gallery's masonry.
    var thumbHeight: CGFloat = 180
    /// "expires in 2 d", shown after the site in the note color (S-021).
    var warning: String?
    /// Search terms to highlight in the title (S-031).
    var highlight: [String] = []

    var isNote: Bool { if case .note = body { true } else { false } }
}

/// A thumbnail: a real image, or a placeholder while the preview loads.
enum CardThumb {
    case image(NSImage)
    /// The preview is still being fetched.
    case loading
}

// MARK: - Card chrome (a ButtonStyle, so cards are real, focusable controls)

struct BlockCardStyle: ButtonStyle {
    var tint: UInt32?
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, tint: tint, isSelected: isSelected)
    }

    private struct Part: View {
        let configuration: Configuration
        let tint: UInt32?
        let isSelected: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            // Cards never draw a focus ring. The Gallery holds keyboard focus for the whole grid,
            // and SwiftUI reports every button inside a focused container as focused, which put a
            // ring on every card. The selected card's ring is the keyboard cue instead.
            let state = PartState.resolve(forced: forced, enabled: isEnabled, selected: isSelected,
                                          pressed: configuration.isPressed, hovering: hovering, focused: false)
            let shape = RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous)
            configuration.label
                .background(Ink.card(tint: tint))
                .clipShape(shape)
                .overlay(shape.strokeBorder(state == .selected || state == .focused ? Ink.accentText : Ink.hairline,
                                            lineWidth: state == .selected || state == .focused ? 2 : state.isActive ? 1.5 : 1))
                .shadow(color: state == .hover ? Ink.shadow : .clear, radius: 12, y: 4)
                .offset(y: state == .hover && !reduceMotion ? -1 : 0) // grid: ok hover lift from KIT.md "Card"
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(shape)
                .kitPress(state)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : Motion.hover, value: hovering)
                .accessibilityAddTraits(state == .selected ? .isSelected : [])
        }
    }
}

// MARK: - Search highlight

/// Marks the words a search matched: accent text on the suggest fill.
enum Highlight {
    static func text(_ text: String, terms: [String]) -> AttributedString {
        var out = AttributedString(text)
        for range in Search.ranges(in: text, terms: terms) {
            guard let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].backgroundColor = Ink.suggest
            out[lower..<upper].foregroundColor = Ink.accentText
        }
        return out
    }
}

// MARK: - Card content

struct BlockCardView: View {
    let content: CardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch content.body {
            case .visual(let thumb):
                ThumbView(thumb: thumb, badge: content.badge)
                    .frame(maxWidth: .infinity)
                    .frame(height: content.thumbHeight)
                    .clipped()
            case .place:
                MapThumb().frame(height: content.thumbHeight * 0.8)
            case .note, .checklist, .plain:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: Metric.inlineGap) {
                Text(content.kindLabel.uppercased())
                    .kitType(.kind)
                    .foregroundStyle(content.isNote ? Ink.noteLabel : Ink.secondary)
                Text(Highlight.text(content.title, terms: content.highlight))
                    .kitType(.cardTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                switch content.body {
                case .note(let text):
                    Text(text).kitType(.body).foregroundStyle(Ink.text.opacity(0.85)).lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                case .checklist(let lines):
                    VStack(alignment: .leading, spacing: Metric.inlineGap) {
                        ForEach(lines.prefix(4)) { line in
                            Toggle(line.text, isOn: .constant(line.done)).toggleStyle(KitCheckStyle())
                        }
                    }
                    .padding(.top, 2)
                default:
                    EmptyView()
                }
                HStack(spacing: Metric.inlineGap) {
                    Text(content.site).kitType(.meta).foregroundStyle(Ink.secondary).lineLimit(1)
                    if let warning = content.warning {
                        Text("· \(warning)").kitType(.metaStrong).foregroundStyle(Ink.noteLabel).lineLimit(1)
                    }
                }
            }
            .padding(Metric.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ThumbView: View {
    let thumb: CardThumb
    var badge: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch thumb {
            case .image(let image):
                // The picture fills the space the card gives it and never sets the card's size:
                // a scaled-to-fill image reports its overflowing size, so it goes in an overlay
                // on a shape that takes exactly the offered space (#6, #8).
                Color.clear
                    .overlay { Image(nsImage: image).resizable().scaledToFill() }
                    .clipped()
            case .loading:
                Ink.control.overlay { ProgressView().controlSize(.small) }
            }
            if let badge { KitBadge(text: badge).padding(Metric.badgeInset) }
        }
        .accessibilityHidden(true)
    }
}

/// A place's thumbnail: a quiet map grid with a pin.
struct MapThumb: View {
    var body: some View {
        ZStack {
            Canvas { context, size in
                let step: CGFloat = 22
                var grid = Path()
                stride(from: 0, through: size.width, by: step).forEach { x in grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height)) }
                stride(from: 0, through: size.height, by: step).forEach { y in grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y)) }
                context.stroke(grid, with: .color(Ink.mapGrid), lineWidth: 1)
                let road = CGRect(x: 0, y: size.height * 0.58, width: size.width, height: Metric.mapRoad)
                context.fill(Path(road), with: .color(Ink.mapRoad))
            }
            .background(Ink.mapGround)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Ink.onChosen, Ink.accentText)
        }
        .accessibilityHidden(true)
    }
}
