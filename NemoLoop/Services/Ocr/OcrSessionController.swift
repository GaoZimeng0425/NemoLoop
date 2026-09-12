import AppKit
import ScreenCaptureKit

/// Orchestrates the whole OCR blade flow: ring commit → permission (preflight +
/// floating logo drag-in) → region selection → capture → recognize → translate
/// → clipboard + preview panel (or the empty-result toast).
@MainActor
final class OcrSessionController {
    static let shared = OcrSessionController()

    /// What happens to the captured region.
    enum CaptureMode {
        case ocr   // selection → recognize → translate → preview panel
        case snip  // selection → pixels straight to the clipboard

        var isOcrFlow: Bool { self == .ocr }
    }

    private var mode: CaptureMode = .ocr
    private var selectionPanel: OcrSelectionPanel?
    private var permissionPanel: OcrPermissionPanel?
    private var resultPanel: OcrResultPanel?

    func handleOcrRequested() {
        handleRequested(mode: .ocr)
    }

    func handleRequested(mode: CaptureMode) {
        guard selectionPanel == nil, permissionPanel == nil else { return }
        self.mode = mode
        if CGPreflightScreenCaptureAccess() {
            startSelection()
        } else {
            startPermissionFlow()
        }
    }

    // MARK: - Selection

    private func startSelection() {
        let screen = screenUnderMouse()
        let panel = OcrSelectionPanel(screen: screen)
        selectionPanel = panel
        panel.beginSelection(onSelect: { [weak self, weak panel] rect in
            // Hand the window number over before the panel closes; the capture
            // excludes our own overlay via "windows below" and waits a tick so
            // the closing panel leaves the screen.
            let windowNumber = panel?.windowNumber ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self?.process(rect: rect, screen: screen, excluding: windowNumber)
            }
        }, onAbort: { [weak self] in
            self?.selectionPanel = nil
        })
    }

    private func process(rect: CGRect, screen: NSScreen, excluding windowNumber: Int = 0) {
        selectionPanel = nil
        Task {
            do {
                let image = try await Self.capture(rect: rect, screen: screen,
                                                   excluding: CGWindowID(windowNumber))
                if mode == .snip {
                    // Pixel dimensions as point size keep the full-resolution
                    // bitmap when the pasteboard consumer reads it back.
                    let snip = NSImage(cgImage: image,
                                       size: NSSize(width: image.width, height: image.height))
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([snip])
                    ToastService.shared.show(.success, "Snipped to clipboard")
                    return
                }
                let lines = OcrTextProcessor.sortedLines(try await OcrEngine.recognize(in: image))
                guard !lines.isEmpty else {
                    ToastService.shared.show(.info, "No text recognized")
                    return
                }
                // Translate only confidently-English lines (en→zh, on-device).
                let translations = await OcrTranslationService.translateToChinese(
                    lines.map { OcrTextProcessor.shouldTranslate($0) ? $0.text : "" })
                var rows: [OcrResultModel.Row] = []
                var translationIndex = 0
                for line in lines {
                    var translated: String?
                    if OcrTextProcessor.shouldTranslate(line) {
                        translated = translations[translationIndex]
                        translationIndex += 1
                    }
                    rows.append(OcrResultModel.Row(id: rows.count,
                                                   original: line.text,
                                                   translated: translated))
                }
                showResult(rows: rows, near: rect, screen: screen)
            } catch {
                LogService.error("OCR failed (\(error))", category: "OCR")
                let detail = String(error.localizedDescription.prefix(48))
                ToastService.shared.show(.error, "OCR failed: \(detail)")
            }
        }
    }

    /// Region capture via ScreenCaptureKit. CGWindowListCreateImage is
    /// unavailable on modern SDKs; SCScreenshotManager does the same job —
    /// grab the mouse's display with our own selection panel excluded.
    private static func capture(rect: CGRect, screen: NSScreen,
                                excluding excludedWindow: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Match by CGDirectDisplayID: frame equality misfires on multi-display
        // setups where SCDisplay.frame disagrees with NSScreen.frame (units /
        // scaling), which selected the WRONG display and made sourceRect land
        // outside it — SCStreamError -3812 "invalid parameter".
        let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let display = content.displays.first { $0.displayID == screenID } ?? content.displays.first
        guard let display else {
            throw NSError(domain: "OcrSessionController", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no capturable display"])
        }
        var excluded: [SCWindow] = []
        if excludedWindow != 0 {
            excluded = content.windows.filter { $0.windowID == excludedWindow }
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        // Selection rect is top-left screen-local. Map it PROPORTIONALLY onto
        // display.frame's size (unit-agnostic), but keep the result
        // DISPLAY-LOCAL — sourceRect rejects global coordinates and fails
        // with SCStreamError -3812 "invalid parameter" whenever the display
        // origin isn't (0,0) (e.g. the external screen at x=-2560).
        let relX = (rect.minX / screen.frame.width).clamped(to: 0...1)
        let relY = 1 - (rect.maxY / screen.frame.height).clamped(to: 0...1)
        let relW = (rect.width / screen.frame.width).clamped(to: 0...1)
        let relH = (rect.height / screen.frame.height).clamped(to: 0...1)
        let source = CGRect(x: relX * display.frame.width,
                            y: relY * display.frame.height,
                            width: relW * display.frame.width,
                            height: relH * display.frame.height)
        guard source.width >= 1, source.height >= 1 else {
            throw NSError(domain: "OcrSessionController", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "degenerate selection rect"])
        }

        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = source
        config.width = max(Int(rect.width * scale), 1)
        config.height = max(Int(rect.height * scale), 1)
        config.showsCursor = false
        // ignoreShadowsSingleWindow is a WINDOW-filter-only property; setting
        // it on a display filter got rejected as an invalid parameter.
        config.captureResolution = .best
        // .info, not .debug: release builds run at dynamicLogLevel = .info,
        // so a debug line never reaches the file log when diagnosing deploys.
        LogService.info("capture source=\(source) px=\(config.width)x\(config.height) display=\(display.displayID) frame=\(display.frame)", category: "OCR")
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func showResult(rows: [OcrResultModel.Row], near rect: CGRect, screen: NSScreen) {
        resultPanel?.close()
        let panel = OcrResultPanel(rows: rows, near: rect, screen: screen)
        panel.makeKeyAndOrderFront(nil)
        resultPanel = panel
    }

    // MARK: - Permission

    private func startPermissionFlow() {
        // Summon the system permission dialog, then park the draggable logo
        // card below it for the drag-in grant.
        _ = CGRequestScreenCaptureAccess()
        let screen = screenUnderMouse()
        let panel = OcrPermissionPanel(screen: screen)
        panel.onGranted = { [weak self] in
            self?.startSelection()
        }
        permissionPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

private extension CGFloat {
    /// `min(max(self, range.lowerBound), range.upperBound)` — used by the
    /// capture source-rect mapping to keep ratios inside the display.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

