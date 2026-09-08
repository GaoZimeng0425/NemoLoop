import AppKit
import Luminare
import SwiftUI

/// Post-recognition result panel: per-line checkboxes (default all selected),
/// Copy copies the checked lines, × / Esc closes. Nonactivating — clicks land
/// here without stealing focus from the app the user was working in.
final class OcrResultPanel: NSPanel {
    /// Late-wired close: the panel can't capture self before super.init.
    private final class CloseBox {
        var onClose: (() -> Void)?
    }

    init(rows: [OcrResultModel.Row], near rect: CGRect, screen: NSScreen) {
        let width: CGFloat = 300
        let model = OcrResultModel(rows: rows)
        let box = CloseBox()
        let content = OcrResultView(model: model) { box.onClose?() }
        let height = min(OcrResultView.height(for: rows.count) + 52, screen.visibleFrame.height - 40)
        let origin = Self.anchor(width: width, height: height,
                                 near: rect, in: screen)
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: content)
        box.onClose = { [weak self] in self?.close() }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// Bottom-right of the selection, nudged fully on-screen.
    private static func anchor(width: CGFloat, height: CGFloat,
                               near rect: CGRect, in screen: NSScreen) -> NSPoint {
        // rect is top-left origin within the screen; convert to same space.
        let x = max(screen.frame.minX + 8,
                    min(rect.maxX - width, screen.frame.maxX - width - 8))
        let y = max(screen.frame.minY + 8,
                    min(rect.minY - height - 8, screen.frame.maxY - height - 8))
        return NSPoint(x: x, y: y)
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

    static func height(for rowCount: Int) -> CGFloat {
        CGFloat(min(rowCount, 8)) * 44 + 16
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OCR")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    let text = OcrTextProcessor.clipboardText(
                        model.rows.map { ($0.translated ?? $0.original, $0.isSelected) })
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Text("Copy")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.luminareCompact)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        OcrResultRowView(row: binding(for: row))
                        Divider()
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

private struct OcrResultRowView: View {
    @Binding var row: OcrResultModel.Row

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(row.isSelected ? Color.accentColor : .secondary)
                .onTapGesture { row.isSelected.toggle() }
            VStack(alignment: .leading, spacing: 2) {
                if let translated = row.translated {
                    Text(translated)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(row.original)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(row.original)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { row.isSelected.toggle() }
    }
}
