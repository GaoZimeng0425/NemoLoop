import AppKit

/// Floating, draggable logo card shown while screen-recording permission is
/// missing: the user drags the logo INTO the system permission dialog's drop
/// zone (macOS 26 flow). Polls the preflight API — once granted, the panel
/// dismisses itself and the OCR selection starts automatically.
final class OcrPermissionPanel: NSPanel {
    var onGranted: (() -> Void)?
    private var pollTimer: Timer?

    init(screen: NSScreen) {
        let size = NSSize(width: 150, height: 150)
        // Best effort: park it below the (system-owned, centered) permission
        // dialog so the drop zone and the logo are both in view.
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
        standardWindowButton(.closeButton)?.isHidden = true

        let stack = NSStackView(frame: NSRect(origin: .zero, size: size))
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        let logo = NSImageView(image: NSImage(named: "MenubarLogo") ?? NSImage())
        logo.image?.isTemplate = false
        logo.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
        stack.addArrangedSubview(logo)
        let label = NSTextField(wrappingLabelWithString: "Drag me into the permission dialog")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 140, height: 30)
        stack.addArrangedSubview(label)
        let openSettings = NSButton(title: "Open System Settings", target: nil, action: nil)
        openSettings.bezelStyle = .rounded
        openSettings.font = .systemFont(ofSize: 11)
        openSettings.controlSize = .small
        openSettings.frame = NSRect(x: 0, y: 0, width: 140, height: 22)
        openSettings.target = self
        openSettings.action = #selector(openSettingsClicked)
        stack.addArrangedSubview(openSettings)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        contentView = stack
        stack.frame = NSRect(origin: .zero, size: size)
        stack.autoresizingMask = [.width, .height]

        startPolling()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
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
