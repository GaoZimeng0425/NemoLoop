// NemoLoop/Helpers/SymbolPlate.swift
import AppKit

/// Monochrome symbol drawn at app-icon size, tinted systemGray so it reads
/// on both the near-white card stock and the dark charcoal one.
enum SymbolPlate {
    static func image(symbolName: String, label: String) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            return img
        }
        var configured = base.withSymbolConfiguration(.init(pointSize: 22, weight: .medium))
        configured = configured?.withSymbolConfiguration(.init(paletteColors: [.systemGray]))
        configured?.draw(in: NSRect(origin: .zero, size: size),
                         from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        return img
    }
}
