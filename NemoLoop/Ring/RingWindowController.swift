// NemoLoop/Ring/RingWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class RingWindowController {
    private var panel: RingPanel?

    var isVisible: Bool { panel != nil }

    /// Screen that currently contains the mouse cursor (falls back to main).
    func screenForCursor() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func show(content: some View, centeredAtGlobalPoint center: CGPoint, onCancel: @escaping () -> Void) {
        hide()
        let screen = screenForCursor()
        let panel = RingPanel(contentRect: screen.frame)
        panel.onCancel = onCancel

        // Convert global (bottom-left) center to the hosting view's top-left coords.
        let local = CGPoint(x: center.x - screen.frame.minX,
                            y: screen.frame.maxY - center.y)

        let host = NSHostingView(rootView: content.environment(\.ringCenter, local))
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = host
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// Passes the ring's center (top-left view coords) down to RingView.
private struct RingCenterKey: EnvironmentKey {
    static let defaultValue: CGPoint = .zero
}
extension EnvironmentValues {
    var ringCenter: CGPoint {
        get { self[RingCenterKey.self] }
        set { self[RingCenterKey.self] = newValue }
    }
}
