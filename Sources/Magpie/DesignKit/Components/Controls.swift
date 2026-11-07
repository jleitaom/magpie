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
                .trim(from: 0, to: Double(min(days, 7)) / 7)
                .stroke(Ink.accentText, style: StrokeStyle(lineWidth: Metric.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Metric.ring - Metric.ringStroke, height: Metric.ring - Metric.ringStroke)
        .accessibilityHidden(true)
    }
}
