import SwiftUI

// MARK: - Pill bar (the floating capsule that holds tabs)

struct KitPillBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(Metric.pillInset)
            .background(Capsule().fill(Ink.surface))
            .overlay(Capsule().strokeBorder(Ink.hairline))
            .shadow(color: Ink.shadow, radius: Metric.barShadowRadius, y: 6)
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
