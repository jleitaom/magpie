import SwiftUI

// MARK: - Button (primary, secondary, ghost)

struct KitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, kind: kind, large: large)
    }

    private struct Part: View {
        let configuration: Configuration
        let kind: Kind
        let large: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, pressed: configuration.isPressed,
                                          hovering: hovering, focused: isFocused)
            let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            configuration.label
                .lineLimit(1)
                .fixedSize()
                .kitType(large ? .labelStrong : .label)
                .foregroundStyle(kind == .primary ? Ink.onAccent : Ink.text)
                .padding(.horizontal, large ? Metric.buttonPadding + 4 : Metric.buttonPadding)
                .frame(minHeight: large ? Metric.controlLarge : Metric.control)
                .background(shape.fill(fill(state)))
                .overlay(shape.strokeBorder(kind == .secondary ? Ink.hairline : .clear))
                .overlay(shape.fill(kind == .secondary && state.isActive ? Ink.hover : .clear))
                .kitFocusRing(shape, state: state)
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(shape)
                .kitPress(state)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
        }

        private func fill(_ state: PartState) -> Color {
            switch kind {
            case .primary: Ink.accent.opacity(state == .pressed ? 0.8 : state == .hover ? 0.9 : 1)
            case .secondary: Ink.control
            case .ghost: state.isActive ? Ink.hover : .clear
            }
        }
    }
}

extension ButtonStyle where Self == KitButtonStyle {
    static func kit(_ kind: KitButtonStyle.Kind = .primary, large: Bool = false) -> KitButtonStyle {
        KitButtonStyle(kind: kind, large: large)
    }
}

// MARK: - Round button (the + button)

struct KitRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration)
    }

    private struct Part: View {
        let configuration: Configuration
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, pressed: configuration.isPressed,
                                          hovering: hovering, focused: isFocused)
            configuration.label
                .foregroundStyle(Ink.onAccent)
                .frame(width: Metric.roundButton, height: Metric.roundButton)
                .background(Circle().fill(Ink.accent.opacity(state == .pressed ? 0.8 : state == .hover ? 0.9 : 1)))
                .kitFocusRing(Circle(), state: state)
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(Circle())
                .kitPress(state)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Chip

struct KitChipStyle: ButtonStyle {
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
            configuration.label
                .kitType(on ? .labelStrong : .label)
                .foregroundStyle(on ? Ink.accentText : Ink.text)
                .padding(.horizontal, Metric.chipPadding)
                .frame(height: Metric.control)
                .background(Capsule().fill(on ? Ink.suggest : state.isActive ? Ink.hover : .clear))
                .overlay(Capsule().strokeBorder(on ? Ink.accentText : Ink.hairline, lineWidth: on ? 1 : 1.75))
                .kitFocusRing(Capsule(), state: state)
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(Capsule())
                .kitPress(state)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Menu row

struct KitMenuRowStyle: ButtonStyle {
    var swatch: Color?
    var shortcut: String?
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, swatch: swatch, shortcut: shortcut, isSelected: isSelected)
    }

    private struct Part: View {
        let configuration: Configuration
        let swatch: Color?
        let shortcut: String?
        let isSelected: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, selected: isSelected,
                                          pressed: configuration.isPressed, hovering: hovering, focused: isFocused)
            let shape = RoundedRectangle(cornerRadius: Metric.menuRowRadius, style: .continuous)
            HStack(spacing: Space.md) {
                if let swatch {
                    RoundedRectangle(cornerRadius: Metric.swatchRadius).fill(swatch).frame(width: Metric.swatch, height: Metric.swatch)
                }
                configuration.label.kitType(.label).foregroundStyle(Ink.text).lineLimit(1)
                Spacer(minLength: Space.sm)
                if state == .selected {
                    KitIconView(icon: .check, size: 12).foregroundStyle(Ink.accentText)
                } else if let shortcut {
                    Text(shortcut).kitType(.mono).foregroundStyle(Ink.secondary)
                }
            }
            .padding(.horizontal, Metric.rowInset)
            .frame(height: Metric.menuRowHeight)
            .background(shape.fill(state.isActive || state == .selected ? Ink.hover : .clear))
            .kitFocusRing(shape, state: state)
            .opacity(state == .disabled ? 0.4 : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
        }
    }
}
