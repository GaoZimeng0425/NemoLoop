// NemoLoop/Services/Toast/ToastWindowController.swift
import AppKit
import SwiftUI

/// Owns the single shared toast panel. Created once at app launch; observes
/// `service.panelWanted` (NOT `visible`): the window must stay on screen one
/// fade-duration longer than the view state, or the dismiss animation gets
/// cut off when the panel orders out.
@MainActor
final class ToastWindowController {
    private let service: ToastService
    private var panel: NSPanel?
    private var host: NSHostingView<ToastView>?

    init(service: ToastService) {
        self.service = service
        observe()
    }

    /// Pure positioning math (unit-tested): horizontal center of the screen's
    /// visible area, 72pt above its bottom edge — clears the Dock on any
    /// screen configuration.
    nonisolated static func toastFrame(contentSize: NSSize, in visibleFrame: CGRect) -> NSRect {
        NSRect(x: visibleFrame.midX - contentSize.width / 2,
               y: visibleFrame.minY + 72,
               width: contentSize.width,
               height: contentSize.height)
    }

    private func observe() {
        withObservationTracking {
            _ = service.panelWanted
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                observe() // re-arm before applying so no change is missed
                apply()
            }
        }
    }

    private func apply() {
        if service.panelWanted {
            present()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func present() {
        let screen = screenUnderMouse()
        if panel == nil {
            let panel = NSPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false            // shadow drawn by ToastView
            panel.level = .screenSaver         // above the ring's .popUpMenu
            panel.ignoresMouseEvents = true    // pure notification, click-through
            panel.isMovable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .ignoresCycle, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: ToastView(service: service))
            host.wantsLayer = true
            host.layer?.backgroundColor = .clear
            panel.contentView = host
            self.panel = panel
            self.host = host
        }
        // Re-measure on every show: the capsule sizes to its content.
        guard let host, let panel else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        host.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(Self.toastFrame(contentSize: size, in: screen.visibleFrame),
                       display: false)
        panel.orderFrontRegardless()
    }

    private func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
