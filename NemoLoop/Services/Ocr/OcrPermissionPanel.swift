import AppKit

/// Floating card shown while screen-recording permission is missing: a
/// horizontal strip with the app logo + name that the user drags INTO the
/// system permission dialog's drop zone (macOS 26 flow). Polls the preflight
/// API — once granted, the panel dismisses itself and OCR selection starts.
final class OcrPermissionPanel: NSPanel {
    var onGranted: (() -> Void)?
    private var pollTimer: Timer?

    init(screen: NSScreen) {
        let size = NSSize(width: 232, height: 104)
        // Best effort: park it below the (system-owned, centered) permission
        // dialog so the drop zone and the card are both in view.
        let origin = NSPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.midY - size.height / 2 - 180)
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let card = WindowDragCardView(frame: NSRect(origin: .zero, size: size))
        card.buildContent()
        contentView = card

        startPolling()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, CGPreflightScreenCaptureAccess() else { return }
                let granted = self.onGranted
                self.dismiss()
                granted?()
            }
        }
    }

    func dismiss() {
        pollTimer?.invalidate()
        pollTimer = nil
        close()
    }

    @objc private func openSettingsClicked() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The logo is a DRAG SOURCE: dragging it offers the app's own file URL, so it
/// can be dropped into any drop zone that accepts apps (the card body, in
/// contrast, just moves the window). If no drop zone takes it, the drag simply
/// fades and nothing happens.
final class LogoDragImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(convert(bounds, to: nil), contents: image)
        beginDraggingSession(with: [item], event: event,
                             source: AppFileDragSource.shared)
    }
}

final class AppFileDragSource: NSObject, NSDraggingSource {
    static let shared = AppFileDragSource()

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor draggingContext: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// The card itself: rounded dark strip — logo + app name in a horizontal bar,
/// hint and a settings fallback below. EVERYWHERE on the card drags the window
/// (mouseDown → performDrag; the settings button still wins its own clicks).
final class WindowDragCardView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override var mouseDownCanMoveWindow: Bool { true }

    func buildContent() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.quaternaryLabelColor.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 8

        let logo = LogoDragImageView(frame: NSRect(x: 14, y: 34, width: 40, height: 40))
        logo.image = NSImage(named: "MenubarLogo")
        logo.image?.isTemplate = false
        addSubview(logo)

        let name = NSTextField(labelWithString: "NemoLoop")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.frame = NSRect(x: 64, y: 48, width: 150, height: 20)
        addSubview(name)

        let hint = NSTextField(labelWithString: "Drag me into the permission dialog")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 64, y: 30, width: 160, height: 14)
        addSubview(hint)

        let settings = NSButton(title: "Open System Settings", target: nil, action: nil)
        settings.bezelStyle = .rounded
        settings.controlSize = .small
        settings.font = .systemFont(ofSize: 10)
        settings.frame = NSRect(x: 14, y: 8, width: 150, height: 20)
        settings.target = self
        settings.action = #selector(openSettingsClicked)
        addSubview(settings)
    }

    @objc private func openSettingsClicked() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The logo is a DRAG SOURCE: dragging it offers the app's own file URL, so it
/// can be dropped into any drop zone that accepts apps (the card body, in
/// contrast, just moves the window). If no drop zone takes it, the drag simply
/// fades and nothing happens.
