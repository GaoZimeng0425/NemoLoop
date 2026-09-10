import AppKit
import ScreenCaptureKit
import SwiftUI

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
                NSLog("NemoLoop OCR: failed (\(error))")
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
        let display = content.displays.first { $0.frame == screen.frame } ?? content.displays.first
        guard let display else {
            throw NSError(domain: "OcrSessionController", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no capturable display"])
        }
        var excluded: [SCWindow] = []
        if excludedWindow != 0 {
            excluded = content.windows.filter { $0.windowID == excludedWindow }
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        // Selection rect is top-left screen-local; SCScreenshot wants a
        // bottom-left display-local rect.
        let global = CGRect(x: screen.frame.minX + rect.minX,
                            y: screen.frame.minY + (screen.frame.height - rect.maxY),
                            width: rect.width, height: rect.height)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: global.minX - display.frame.minX,
                                   y: global.minY - display.frame.minY,
                                   width: rect.width, height: rect.height)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
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

