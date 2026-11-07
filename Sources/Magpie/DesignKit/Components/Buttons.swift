import MagpieKit
import SwiftUI

// MARK: - Button (primary, secondary, ghost)

struct KitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary
    var large = false
    /// False inside a view that holds keyboard focus for its whole area (the Gallery):
    /// SwiftUI reports every button in it as focused, which would draw a ring on each.
    var showsFocus = true

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, kind: kind, large: large, showsFocus: showsFocus)
    }

    private struct Part: View {
        let configuration: Configuration
        let kind: Kind
        let large: Bool
        let showsFocus: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, pressed: configuration.isPressed,
                                          hovering: hovering, focused: isFocused && showsFocus)
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
    static func kit(_ kind: KitButtonStyle.Kind = .primary, large: Bool = false, showsFocus: Bool = true) -> KitButtonStyle {
        KitButtonStyle(kind: kind, large: large, showsFocus: showsFocus)
    }
}

// MARK: - Key button (Sort Inbox's action bar)

/// A large action button that shows its key: a key cap, then the label. The prominent one
/// (the main action) is filled with the accent.
struct KitKeyButtonStyle: ButtonStyle {
    let key: String
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, key: key, prominent: prominent)
    }

    private struct Part: View {
        let configuration: Configuration
        let key: String
        let prominent: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, pressed: configuration.isPressed,
                                          hovering: hovering, focused: isFocused)
            let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            HStack(spacing: Space.sm) {
                Text(key)
                    .kitType(key.count == 1 && key.first!.isLetter ? .mono : .labelStrong)
                    .foregroundStyle(prominent ? Ink.onAccent : Ink.text)
                    .frame(minWidth: Metric.keyCap, minHeight: Metric.keyCap)
                    .background(RoundedRectangle(cornerRadius: Metric.radiusBadge).fill(prominent ? Ink.onAccent.opacity(0.2) : Ink.control))
                configuration.label.kitType(.label).foregroundStyle(prominent ? Ink.onAccent : Ink.text)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, Metric.rowInset)
            .padding(.trailing, Metric.buttonPadding)
            .frame(height: Metric.controlLarge)
            .background(shape.fill(prominent ? Ink.accent.opacity(state == .pressed ? 0.8 : state == .hover ? 0.9 : 1)
                                             : state.isActive ? Ink.control : Ink.surface))
            .overlay(shape.strokeBorder(prominent ? .clear : Ink.hairline))
            .kitFocusRing(shape, state: state)
            .opacity(state == .disabled ? 0.4 : 1)
            .contentShape(shape)
            .kitPress(state)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .accessibilityHint("Shortcut: \(key)")
        }
    }
}

// MARK: - Pile tile (Lucky Dip)

/// A pile to dip into: icon, name, "8 waiting · 3 h 10 min". Selected: teal ring and fill.
struct KitPileTileStyle: ButtonStyle {
    let icon: KitIcon
    let detail: String
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, icon: icon, detail: detail, isSelected: isSelected)
    }

    private struct Part: View {
        let configuration: Configuration
        let icon: KitIcon
        let detail: String
        let isSelected: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, selected: isSelected,
                                          pressed: configuration.isPressed, hovering: hovering, focused: isFocused)
            let on = state == .selected
            let shape = RoundedRectangle(cornerRadius: Metric.radiusCard - 2, style: .continuous)
            HStack(spacing: Space.md) {
                KitIconView(icon: icon, size: 16)
                    .foregroundStyle(on ? Ink.accentText : Ink.secondary)
                    .frame(width: Metric.control, height: Metric.control)
                    .background(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous).fill(on ? Ink.surface : Ink.control))
                VStack(alignment: .leading, spacing: 2) {
                    configuration.label.kitType(.labelStrong).foregroundStyle(Ink.text)
                    Text(detail).kitType(.meta).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .background(shape.fill(on ? Ink.suggest : state.isActive ? Ink.control : Ink.surface))
            .overlay(shape.strokeBorder(on ? Ink.accentText : Ink.hairline, lineWidth: on ? 1.5 : 1))
            .kitFocusRing(shape, state: state)
            .opacity(state == .disabled ? 0.4 : 1)
            .contentShape(shape)
            .kitPress(state)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
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
                .lineLimit(1)
                .fixedSize()
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
