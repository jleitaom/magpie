import AppKit
import SwiftUI

/// "Saved to Inbox": a small label that floats above the Dock for two seconds after a Dock
/// drop, without bringing Magpie forward or taking the keyboard (S-041).
@MainActor
enum DropHUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ text: String) {
        let panel = panel ?? make()
        Self.panel = panel
        panel.contentView = NSHostingView(rootView: Label(text: text))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 220, height: 44))
        // Centered just above the Dock (the bottom of the visible area) on the screen with the mouse.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + Metric.hudLift))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderOut(nil)
            } else {
                await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 }
                panel.orderOut(nil)
            }
        }
    }

    static var isVisible: Bool { panel?.isVisible ?? false }
    static var window: NSWindow? { panel }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private struct Label: View {
        let text: String

        var body: some View {
            HStack(spacing: Space.sm) {
                KitIconView(icon: .check, size: 12).foregroundStyle(Ink.accentText)
                Text(text).kitType(.labelStrong).foregroundStyle(Ink.text)
            }
            .padding(.horizontal, Space.lg)
            .frame(height: Metric.controlLarge)
            .background(Capsule().fill(Ink.surface))
            .overlay(Capsule().strokeBorder(Ink.hairline))
            .fixedSize()
        }
    }
}
