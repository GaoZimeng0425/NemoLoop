import AppKit

/// Full-screen single-screen overlay for ⌘⇧4-style region selection: dimmed
/// background, crosshair cursor, drag a rectangle, release to commit. Clicks
/// without a drag are ignored (keeps the session alive); Esc aborts.
final class OcrSelectionPanel: NSPanel {
    var onSelect: ((CGRect) -> Void)?   // screen coords, top-left origin
    var onAbort: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = OcrSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
        onAbort?()
    }

    private var selectionView: OcrSelectionView? { contentView as? OcrSelectionView }

    func beginSelection(onSelect: @escaping (CGRect) -> Void, onAbort: @escaping () -> Void) {
        self.onSelect = { rect in
            self.close()
            onSelect(rect)
        }
        self.onAbort = onAbort
        selectionView?.onSelect = { [weak self] rect in self?.onSelect?(rect) }
        makeKeyAndOrderFront(nil)
    }
}

final class OcrSelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?

    private var dragStart: NSPoint?
    private var dragRect: CGRect = .zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let here = convert(event.locationInWindow, from: nil)
        dragRect = CGRect(x: min(start.x, here.x), y: min(start.y, here.y),
                          width: abs(here.x - start.x), height: abs(here.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = dragRect
        dragStart = nil
        dragRect = .zero
        needsDisplay = true
        // A plain click (no meaningful drag) is ignored — the session stays
        // open so the user can try again; Esc aborts.
        guard rect.width >= 12, rect.height >= 12 else { return }
        onSelect?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything except the selection rectangle (even-odd leaves a hole),
        // then outline the selection.
        let dim = NSBezierPath(rect: bounds)
        if dragRect.width > 0, dragRect.height > 0 {
            dim.append(NSBezierPath(rect: dragRect))
        }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.30).setFill()
        dim.fill()

        guard dragRect.width > 0, dragRect.height > 0 else { return }
        let border = NSBezierPath(rect: dragRect.insetBy(dx: -0.75, dy: -0.75))
        border.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()
    }
}
