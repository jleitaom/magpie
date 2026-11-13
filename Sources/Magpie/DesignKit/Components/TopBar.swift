import AppKit
import SwiftUI

// MARK: - Pill bar (the floating capsule that holds tabs)

struct KitPillBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(Metric.pillInset)
            .background(Capsule().fill(Ink.surface))
            .overlay(Capsule().strokeBorder(Ink.hairline))
            .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: Metric.barShadowY)
    }
}

/// A thin divider between groups inside a pill bar.
struct KitBarDivider: View {
    var body: some View {
        Capsule().fill(Ink.hairline).frame(width: 1, height: Metric.dividerHeight).padding(.horizontal, Space.xs)
    }
}

// MARK: - Tab

struct KitTabStyle: ButtonStyle {
    var isSelected = false
    var count: Int?

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, isSelected: isSelected, count: count)
    }

    private struct Part: View {
        let configuration: Configuration
        let isSelected: Bool
        let count: Int?
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, selected: isSelected,
                                          pressed: configuration.isPressed, hovering: hovering, focused: isFocused)
            let on = state == .selected
            HStack(spacing: Metric.inlineGap) {
                configuration.label.kitType(on ? .labelStrong : .label).lineLimit(1)
                if let count, count > 0 {
                    Text("\(count)").kitType(.metaStrong).foregroundStyle(on ? Ink.onChosen : Ink.accentText)
                }
            }
            .fixedSize()
            .foregroundStyle(on ? Ink.onChosen : state == .rest || state == .disabled ? Ink.secondary : Ink.text)
            .padding(.horizontal, Metric.tabPadding)
            .frame(height: Metric.control)
            .background(Capsule().fill(on ? Ink.chosen : state.isActive ? Ink.hover : .clear))
            .kitFocusRing(Capsule(), state: state)
            .opacity(state == .disabled ? 0.4 : 1)
            .contentShape(Capsule())
            .kitPress(state)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

// MARK: - Tab field (rename in place)

/// A tab whose name is being edited where it stands in the top bar. Same size and type as
/// a selected tab, with a teal ring. It opens with the whole name selected, so typing replaces
/// it. Return saves, Escape cancels, clicking away saves.
struct KitTabField: View {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @State private var hadFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        // The hidden text sizes the field to the name as it's typed.
        Text(text.isEmpty ? initial : text)
            .kitType(.labelStrong)
            .hidden()
            .overlay(alignment: .leading) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .kitType(.labelStrong)
                    .foregroundStyle(Ink.text)
                    .focused($focused)
                    .onSubmit { onCommit(text) }
                    .onExitCommand(perform: onCancel)
            }
            .padding(.trailing, Space.xs)  // room for the cursor after the last letter
            .fixedSize()
            .padding(.horizontal, Metric.tabPadding)
            .frame(height: Metric.control)
            .background(Capsule().fill(Ink.control))
            .overlay(Capsule().strokeBorder(Ink.accentText, lineWidth: Metric.focusRing))
            .task {
                text = initial
                await kitFocusAndSelectAll { focused = true; return focused }
                hadFocus = true
            }
            .onChange(of: focused) { _, now in
                if !now, hadFocus { onCommit(text) }
            }
            .accessibilityLabel("Collection name")
    }
}

/// Gives a text field focus, asking again while a panel or menu is still settling, then selects
/// all of its text so typing replaces it. `focus` sets the field's FocusState and returns it.
@MainActor
func kitFocusAndSelectAll(_ focus: () -> Bool) async {
    for _ in 0..<10 {
        if focus() { break }
        try? await Task.sleep(for: .milliseconds(100))
    }
    try? await Task.sleep(for: .milliseconds(50))
    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
}

// MARK: - Search field (top bar)

/// The search field that takes the tabs' place while you search (S-031): a magnifier, the field,
/// the number of results, and a close button. Escape closes it.
struct KitSearchField: View {
    @Binding var text: String
    let results: Int
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            KitIconView(icon: .search).foregroundStyle(Ink.secondary)
            TextField("Search titles, notes, links, tags and text in images", text: $text)
                .textFieldStyle(.plain)
                .kitType(.label)
                .foregroundStyle(Ink.text)
                .focused($focused)
                .onExitCommand(perform: onClose)
            if !text.isEmpty {
                Text(results == 1 ? "1 result" : "\(results) results").kitType(.meta).foregroundStyle(Ink.secondary).fixedSize()
            }
            Button(action: onClose) { KitIconView(icon: .close, size: Metric.chevron) }
                .buttonStyle(.kit(.ghost))
                .help("Close search (Esc)")
                .accessibilityLabel("Close search")
        }
        .padding(.leading, Space.lg)
        .padding(.trailing, Metric.pillInset)
        .frame(width: Metric.searchWidth, height: Metric.control + Metric.pillInset * 2)
        .background(Capsule().fill(Ink.surface))
        .overlay(Capsule().strokeBorder(focused ? Ink.accentText : Ink.hairline, lineWidth: focused ? 1.5 : 1))
        .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: Metric.barShadowY)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search")
    }
}

// MARK: - Segment (view switcher)

/// The track around segments.
struct KitSegmentTrack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(Metric.trackInset)
            .background(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous).fill(Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous).strokeBorder(Ink.hairline))
    }
}

struct KitSegmentStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, isSelected: isSelected)
    }

    private struct Part: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, selected: isSelected,
                                          pressed: configuration.isPressed, hovering: hovering, focused: isFocused)
            let on = state == .selected
            let shape = RoundedRectangle(cornerRadius: Metric.segmentRadius, style: .continuous)
            configuration.label
                .foregroundStyle(on ? Ink.onChosen : state == .rest ? Ink.secondary : Ink.text)
                .frame(width: Metric.segmentWidth, height: Metric.segmentHeight)
                .background(shape.fill(on ? Ink.chosen : state.isActive ? Ink.hover : .clear))
                .kitFocusRing(shape, state: state)
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(shape)
                .kitPress(state)
                .onHover { hovering = $0 }
                .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}
