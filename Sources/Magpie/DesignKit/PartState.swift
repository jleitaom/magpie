import SwiftUI

/// The one state a part draws. The gallery forces it, so hover and pressed show in snapshots.
enum PartState: String, CaseIterable {
    case rest, hover, pressed, selected, focused, disabled

    /// Resolves a part's state from its inputs, in priority order.
    static func resolve(forced: PartState?, enabled: Bool, selected: Bool = false,
                        pressed: Bool, hovering: Bool, focused: Bool) -> PartState {
        if let forced { return forced }
        if !enabled { return .disabled }
        if pressed { return .pressed }
        if selected { return .selected }
        if focused { return .focused }
        if hovering { return .hover }
        return .rest
    }

    var isActive: Bool { self == .hover || self == .pressed }
}

extension EnvironmentValues {
    @Entry var forcedPartState: PartState?
}

extension View {
    /// The kit's own focus ring: drawn only in `.focused`, outside the shape.
    func kitFocusRing<S: InsettableShape>(_ shape: S, state: PartState) -> some View {
        overlay(shape.inset(by: -Metric.focusRing).strokeBorder(Ink.accentText, lineWidth: state == .focused ? Metric.focusRing : 0))
    }

    /// Scale for pressed parts, instant when Reduce Motion is on.
    func kitPress(_ state: PartState) -> some View {
        modifier(PressEffect(state: state))
    }
}

private struct PressEffect: ViewModifier {
    let state: PartState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(state == .pressed ? Metric.pressScale : 1)
            .animation(reduceMotion ? nil : Motion.press, value: state)
    }
}
