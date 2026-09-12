import AppKit
import SwiftUI

/// Post-recognition result panel: draggable + resizable chrome that remembers
/// its frame across runs (standard window-frame autosave), per-line checkboxes
/// (default all selected), Copy copies the checked lines, × / Esc closes.
/// Nonactivating — clicks land here without stealing focus from the app the
/// user was working in.
final class OcrResultPanel: NSPanel {
    private static let autosaveName = "OCRResultPanel"

    /// Late-wired close: the panel can't capture self before super.init.
    private final class CloseBox {
        var onClose: (() -> Void)?
    }

    init(rows: [OcrResultModel.Row], near rect: CGRect, screen: NSScreen) {
        let model = OcrResultModel(rows: rows)
        let box = CloseBox()
        let content = OcrResultView(model: model) { box.onClose?() }

        let defaultWidth: CGFloat = 320
        let defaultHeight = min(OcrResultView.height(for: rows.count) + 64,
                                screen.visibleFrame.height - 40)
        super.init(contentRect: NSRect(origin: .zero,
                                       size: NSSize(width: defaultWidth, height: defaultHeight)),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Drag from any non-interactive chrome area (header, dividers, footer).
        isMovableByWindowBackground = true
        minSize = NSSize(width: 260, height: 140)
        contentView = NSHostingView(rootView: content)

        // Remember position + size across runs: restore the saved frame, then
        // enroll in autosave so every later move/resize persists. A frame
        // stranded off every screen (display unplugged) re-anchors next to
        // the selection instead.
        let anchor = Self.anchoredFrame(width: defaultWidth, height: defaultHeight,
                                        near: rect, in: screen)
        setFrame(anchor, display: false)
        if setFrameUsingName(Self.autosaveName),
           !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            setFrame(anchor, display: false)
        }
        setFrameAutosaveName(Self.autosaveName)
        box.onClose = { [weak self] in self?.close() }
    }

    override var canBecomeKey: Bool { true }

    /// Fade in instead of appearing at full opacity — a floating panel that
    /// pops in instantly reads as abrupt next to system chrome.
    func present() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// Bottom-right of the selection, nudged fully on-screen.
    private static func anchoredFrame(width: CGFloat, height: CGFloat,
                                      near rect: CGRect, in screen: NSScreen) -> NSRect {
        // rect is top-left origin within the screen; convert to same space.
        let x = max(screen.frame.minX + 8,
                    min(rect.maxX - width, screen.frame.maxX - width - 8))
        let y = max(screen.frame.minY + 8,
                    min(rect.minY - height - 8, screen.frame.maxY - height - 8))
        return NSRect(origin: NSPoint(x: x, y: y),
                      size: NSSize(width: width, height: height))
    }
}

@MainActor
@Observable
final class OcrResultModel {
    struct Row: Identifiable, Equatable {
        let id: Int
        /// Text as recognized on screen.
        let original: String
        /// Present only for en→zh translated rows (the copy text).
        var translated: String?
        var isSelected = true
    }

    var rows: [Row]
    init(rows: [Row]) { self.rows = rows }
}

struct OcrResultView: View {
    @Bindable var model: OcrResultModel
    var onClose: () -> Void

    @State private var justCopied = false
    @State private var hoveredRowID: Int?

    static func height(for rowCount: Int) -> CGFloat {
        CGFloat(min(rowCount, 8)) * 52 + 16
    }

    private var selectedCount: Int { model.rows.filter(\.isSelected).count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.rows) { row in
                        OcrResultRowView(row: binding(for: row),
                                         isHovered: hoveredRowID == row.id)
                            .onHover { hovering in
                                guard hovering else {
                                    if hoveredRowID == row.id { hoveredRowID = nil }
                                    return
                                }
                                hoveredRowID = row.id
                            }
                            .padding(.horizontal, 6)
                            .padding(.top, row.id == model.rows.first?.id ? 6 : 0)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(minWidth: 260, minHeight: 140)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial))
        // Light catches the top edge: a brighter upper stroke over a near-
        // invisible lower one reads as a lit material, not a flat outline.
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                          startPoint: .top, endPoint: .bottom)))
    }

    /// The drag affordance: grip + title live on window-background area, so
    /// dragging anywhere here moves the panel (isMovableByWindowBackground).
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
            Image(systemName: "text.viewfinder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
            Text("OCR Result")
                .font(.system(size: 12, weight: .semibold))
            Text("\(selectedCount)/\(model.rows.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            Spacer()
            HeaderIconButton(icon: justCopied ? "checkmark" : "doc.on.doc",
                             tint: justCopied ? .green : .secondary,
                             help: "Copy selected lines") {
                copySelected()
            }
            HeaderIconButton(icon: "xmark", help: "Close (Esc)") {
                onClose()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text("\(selectedCount) of \(model.rows.count) selected")
            Spacer()
            Text("Drag to move · Esc to close")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func copySelected() {
        NSPasteboard.general.clearContents()
        let text = OcrTextProcessor.clipboardText(
            model.rows.map { ($0.translated ?? $0.original, $0.isSelected) })
        NSPasteboard.general.setString(text, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }

    private func binding(for row: OcrResultModel.Row) -> Binding<OcrResultModel.Row> {
        Binding {
            model.rows.first { $0.id == row.id } ?? row
        } set: { newValue in
            if let idx = model.rows.firstIndex(where: { $0.id == row.id }) {
                model.rows[idx] = newValue
            }
        }
    }
}

/// Header icon button with a hover highlight — a plain button gave no
/// feedback until commit, which reads as dead under the pointer.
private struct HeaderIconButton: View {
    let icon: String
    var tint: Color = .secondary
    let help: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.10 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

private struct OcrResultRowView: View {
    @Binding var row: OcrResultModel.Row
    var isHovered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(row.isSelected
                    ? AnyShapeStyle(.tint)
                    : AnyShapeStyle(.tertiary))
                .onTapGesture { toggle() }
            VStack(alignment: .leading, spacing: 3) {
                if let translated = row.translated {
                    Text(translated)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Text(row.original)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(row.original)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.12)) { row.isSelected.toggle() }
    }
}
