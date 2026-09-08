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

        // THE button — logo + name as one big unit, full card width. Its
        // interaction is DRAG-TO-AUTHORIZE: dragging it offers NemoLoop.app's
        // file URL to whatever permission drop zone accepts it.
        let grant = OcrGrantButtonView(frame: NSRect(x: 12, y: frame.height - 12 - 44,
                                                     width: W - 24, height: 44))
        addSubview(grant)

        // Hint, centered below with equal spacing.
        let hint = NSTextField(labelWithString: "Click to allow screen recording")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        let hintW = ceil(hint.attributedStringValue.size().width)
        hint.frame = NSRect(x: (W - hintW) / 2, y: 12, width: hintW + 4, height: 14)
        addSubview(hint)
    }
}

/// The big logo+name button — pure style + drag source: dragging it offers
/// NemoLoop.app's file URL to permission drop zones. Content is manually
/// centered (borderless NSButton alignment is unreliable).
final class OcrGrantButtonView: NSView {
    private let logo = NSImageView(frame: .zero)
    private let name = NSTextField(labelWithString: "NemoLoop")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
        layer?.cornerRadius = 8

        logo.image = NSImage(named: "MenubarLogo")
        logo.image?.isTemplate = true          // tint white — the raw glyph is dark
        logo.contentTintColor = .white
        logo.frame.size = NSSize(width: 24, height: 24)
        addSubview(logo)

        name.font = .systemFont(ofSize: 15, weight: .semibold)
        addSubview(name)
        layoutContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        let nameW = ceil(name.attributedStringValue.size().width)
        let groupW = 24 + 8 + nameW
        let startX = (bounds.width - groupW) / 2
        logo.frame = NSRect(x: startX, y: (bounds.height - 24) / 2, width: 24, height: 24)
        name.frame = NSRect(x: startX + 32, y: (bounds.height - 20) / 2, width: nameW + 4, height: 20)
    }

    override var mouseDownCanMoveWindow: Bool { false }   // the panel must not move

    /// All points hit THIS view — the logo/name stay render-only, so the
    /// window's move-by-background never steals the press (it used to drag
    /// the whole panel along with the drag session).
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        if let snapshot = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: snapshot)
            if let cg = snapshot.cgImage {
                item.setDraggingFrame(bounds, contents: NSImage(cgImage: cg, size: bounds.size))
            }
        }
        beginDraggingSession(with: [item], event: event, source: AppFileDragSource.shared)
    }
}

final class AppFileDragSource: NSObject, NSDraggingSource {
    static let shared = AppFileDragSource()

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor draggingContext: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
