import AppKit
import ScreenCaptureKit
import SwiftUI

/// Orchestrates the whole OCR blade flow: ring commit → permission (preflight +
/// floating logo drag-in) → region selection → capture → recognize → translate
/// → clipboard + preview panel (or the empty-result toast).
@MainActor
final class OcrSessionController {
    static let shared = OcrSessionController()

    private var selectionPanel: OcrSelectionPanel?
    private var permissionPanel: OcrPermissionPanel?
    private var resultPanel: OcrResultPanel?
    private var toastPanel: NSPanel?
    private var toastTimer: Timer?

    func handleOcrRequested() {
        guard selectionPanel == nil, permissionPanel == nil else { return }
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
                let lines = OcrTextProcessor.sortedLines(try await OcrEngine.recognize(in: image))
                guard !lines.isEmpty else {
                    showToast("No text recognized")
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
                showToast("OCR failed: \(detail)")
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

    // MARK: - Toast

    private func showToast(_ text: String) {
        toastPanel?.orderOut(nil)
        toastTimer?.invalidate()

        let size = NSSize(width: 240, height: 44)
        let screen = screenUnderMouse()
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        _ = frame
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.setFrame(frame, display: true)

        let host = NSHostingView(rootView: AnyView(
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size.width, height: size.height)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.75)))
        ))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.orderFrontRegardless()
        toastPanel = panel

        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.toastPanel?.orderOut(nil)
                self?.toastPanel = nil
            }
        }
    }

    private func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

