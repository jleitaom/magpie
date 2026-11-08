import MagpieKit
import SwiftUI

// MARK: - Check (checklist items)

struct KitCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: Space.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Metric.radiusCheck, style: .continuous)
                        .strokeBorder(Ink.tertiary, lineWidth: configuration.isOn ? 0 : 1.5)
                    if configuration.isOn {
                        RoundedRectangle(cornerRadius: Metric.radiusCheck, style: .continuous).fill(Ink.accentText)
                        KitIconView(icon: .check, size: 8).foregroundStyle(Ink.onChosen)
                    }
                }
                .frame(width: Metric.check, height: Metric.check)
                configuration.label
                    .kitType(.body)
                    .strikethrough(configuration.isOn)
                    .foregroundStyle(configuration.isOn ? Ink.secondary : Ink.text)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Not done")
    }
}

// MARK: - Field

struct KitField: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radiusField, style: .continuous)
        content
            .textFieldStyle(.plain)
            .kitType(.body)
            .foregroundStyle(Ink.text)
            .focused($focused)
            .padding(.horizontal, Metric.rowInset)
            .padding(.vertical, Metric.fieldVertical)
            .frame(minHeight: Metric.control)
            .background(shape.fill(Ink.window))
            .overlay(shape.strokeBorder(focused ? Ink.accentText : Ink.hairline, lineWidth: focused ? 1.5 : 1))
    }
}

extension View {
    func kitField() -> some View { modifier(KitField()) }
}

// MARK: - Badge ("13 min", "€189")

struct KitBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .kitType(.kind)
            .foregroundStyle(Ink.onBadge)
            .padding(Metric.badgePadding)
            .background(RoundedRectangle(cornerRadius: Metric.radiusBadge, style: .continuous).fill(Ink.badge))
    }
}

// MARK: - Panel (details, popovers)

struct KitPanel<Content: View>: View {
    var width: CGFloat = Metric.panelWidth
    var radius: CGFloat = Metric.radiusPanel
    var fill: Color = Ink.surface
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .frame(width: width)
            .background(shape.fill(fill))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Ink.hairline))
            .shadow(color: Ink.shadow, radius: 20, x: -6)
    }
}

// MARK: - Popover surface

extension View {
    /// The background for a popover's content: solid Ink.surface instead of the system's
    /// see-through glass, so cards behind it never show through the text.
    func kitPopover() -> some View {
        presentationBackground(Ink.surface)
    }
}

// MARK: - Banner (a prompt above the cards)

/// A quiet teal prompt with one action, e.g. "8 blocks waiting to be sorted · Start sorting".
struct KitBanner: View {
    let title: String
    let detail: String
    let action: String
    let run: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radiusCard - 2, style: .continuous)
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).kitType(.labelStrong).foregroundStyle(Ink.text)
                Text(detail).kitType(.meta).foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
            // It sits inside the Gallery, which holds keyboard focus, so it draws no focus ring.
            // Its action is in the menu bar (Inbox → Sort Inbox, ⌃⌘3).
            Button(action, action: run).buttonStyle(.kit(showsFocus: false))
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(shape.fill(Ink.suggest))
        .overlay(shape.strokeBorder(Ink.accentText.opacity(0.25)))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Totals strip (a collection's video time and prices)

/// "3 h 10 min of video saved" with an "I have 20 minutes" chip, and "Wishlist total €442 + $60"
/// (S-073, S-074). Shown above the cards of a collection that has lengths or prices.
struct KitTotalsStrip: View {
    let videoTotal: String?
    let priceTotal: String?
    @Binding var fitsTwenty: Bool

    var body: some View {
        HStack(spacing: Space.lg) {
            if let videoTotal {
                let total = Text(videoTotal).foregroundStyle(Ink.text).bold()
                Text("\(total) of video saved").kitType(.body).foregroundStyle(Ink.secondary)
            }
            if let priceTotal {
                let total = Text(priceTotal).foregroundStyle(Ink.text).bold()
                Text("Wishlist total \(total)").kitType(.body).foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
            if videoTotal != nil {
                Button("I have 20 minutes") { fitsTwenty.toggle() }
                    .buttonStyle(KitChipStyle(isSelected: fitsTwenty, showsFocus: false))
                    .help("Only show what fits in 20 minutes")
            } else if priceTotal != nil {
                Text("Prices read when you saved each page").kitType(.meta).foregroundStyle(Ink.secondary)
            }
        }
        .frame(minHeight: Metric.control)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Streak pill (top bar, next to the traffic lights)

/// "6-day streak" with a ring that fills over a week. A button: it opens Sort Inbox.
struct KitStreakPillStyle: ButtonStyle {
    let days: Int

    func makeBody(configuration: Configuration) -> some View {
        Part(configuration: configuration, days: days)
    }

    private struct Part: View {
        let configuration: Configuration
        let days: Int
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let state = PartState.resolve(forced: forced, enabled: isEnabled, pressed: configuration.isPressed,
                                          hovering: hovering, focused: isFocused)
            HStack(spacing: Space.sm) {
                KitStreakRing(days: days)
                configuration.label.kitType(.meta).foregroundStyle(Ink.text)
            }
            .fixedSize()
            .padding(.leading, Space.sm)
            .padding(.trailing, Space.md)
            .frame(height: Metric.streakPill)
            .background(Capsule().fill(state.isActive ? Ink.control : Ink.surface))
            .overlay(Capsule().strokeBorder(Ink.hairline))
            .kitFocusRing(Capsule(), state: state)
            .contentShape(Capsule())
            .kitPress(state)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
        }
    }
}

// MARK: - Stat tile (Inbox zero)

/// A big number over a small label: "5 sorted".
struct KitStatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: Space.xs) {
            Text("\(value)").kitType(.title).foregroundStyle(Ink.text)
            Text(label).kitType(.meta).foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        .background(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous).fill(Ink.surface))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progress bar and streak ring

struct KitProgressBar: View {
    /// 0...1
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.control)
                Capsule().fill(Ink.accentText).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: Metric.progressHeight)
        .animation(reduceMotion ? nil : Motion.progress, value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct KitStreakRing: View {
    /// Days in the streak; the ring fills by 1/7 per day.
    let days: Int

    var body: some View {
        ZStack {
            Circle().stroke(Ink.control, lineWidth: Metric.ringStroke)
            Circle()
                .trim(from: 0, to: Streak.ringFill(days))
                .stroke(Ink.accentText, style: StrokeStyle(lineWidth: Metric.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Metric.ring - Metric.ringStroke, height: Metric.ring - Metric.ringStroke)
        .accessibilityHidden(true)
    }
}
