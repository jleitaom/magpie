import AppKit
import SwiftUI

/// Hides the title bar and centers the traffic lights in the 56 pt top bar band
/// (notes/design/KIT.md "Window"). SwiftUI has no API for the buttons' position, so this
/// reaches the NSWindow. AppKit moves them back on resize, so it re-applies then.
struct WindowChrome: NSViewRepresentable {
    var firstButtonCenter = Metric.trafficLights
    var buttonSpacing = Metric.trafficLightSpacing

    func makeNSView(context: Context) -> NSView {
        let view = ChromeView()
        view.configure = { [firstButtonCenter, buttonSpacing] window in
            Self.configure(window, center: firstButtonCenter, spacing: buttonSpacing)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func configure(_ window: NSWindow, center: CGPoint, spacing: CGFloat) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type), let container = button.superview else { continue }
            let x = center.x + CGFloat(index) * spacing
            button.setFrameOrigin(NSPoint(x: x - button.frame.width / 2,
                                          y: container.frame.height - center.y - button.frame.height / 2))
        }
    }

    private final class ChromeView: NSView {
        var configure: ((NSWindow) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in self?.configure?(window) }
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                         NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.configure?(window) }
                })
            }
        }
    }
}
