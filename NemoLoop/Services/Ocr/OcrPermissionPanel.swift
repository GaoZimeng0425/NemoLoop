import AppKit

/// Floating card shown while screen-recording permission is missing: a compact
/// card whose big logo+name button opens the System Settings screen-recording
/// page (the actual grant path). Polls the preflight API — once granted, the
/// panel dismisses itself and OCR selection starts automatically.
final class OcrPermissionPanel: NSPanel {
    var onGranted: (() -> Void)?
    private var pollTimer: Timer?

    init(screen: NSScreen) {
        let size = NSSize(width: 236, height: 90)
        // Best effort: park it below the (system-owned, centered) permission
        // dialog so both are in view.
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

        let card = OcrPermissionCardView(frame: NSRect(origin: .zero, size: size))
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

/// The card: a distinct rounded dark plate. One big logo+name button (opens
/// System Settings) centered up top, the drag hint centered below — equal
/// 12pt top/bottom padding. Dragging anywhere on the card moves the window.
final class OcrPermissionCardView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildContent() {
        wantsLayer = true
        // A CONCRETE dark card color: semantic pattern colors don't survive the
        // cgColor conversion (the card used to render invisible against the bg).
        layer?.backgroundColor = CGColor(srgbRed: 0.11, green: 0.105, blue: 0.10, alpha: 0.97)
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 8

        let W = frame.width

        // THE button — logo + name as one big unit. Clicking opens the
        // System Settings screen-recording page.
        let button = NSButton(title: "NemoLoop",
                              image: NSImage(named: "MenubarLogo") ?? NSImage(),
                              target: nil, action: nil)
        button.image?.isTemplate = true
        button.image?.size = NSSize(width: 24, height: 24)
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.isBordered = false
        button.bezelStyle = .texturedRounded
        button.alignment = .center        // icon+title centered in the full-width button
        let bh: CGFloat = 44
        button.frame = NSRect(x: 12, y: frame.height - 12 - bh, width: W - 24, height: bh)
        button.wantsLayer = true
        button.layer?.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = #selector(openSettingsClicked)
        addSubview(button)

        // Hint, centered below with equal spacing.
        let hint = NSTextField(labelWithString: "Click to allow screen recording")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        let hintW = ceil(hint.attributedStringValue.size().width)
        hint.frame = NSRect(x: (W - hintW) / 2, y: 12, width: hintW + 4, height: 14)
        addSubview(hint)
    }

    @objc private func openSettingsClicked() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
