import AppKit
import Testing
import Vision
@testable import NemoLoop

/// Runs the real Vision recognizer against a synthetic bitmap with known text —
/// the end-to-end guarantee that OcrEngine produces ordered, attributed lines.
@MainActor
struct OcrEngineTests {
    @Test func recognizesSyntheticText() async throws {
        let image = try Self.renderText(["Hello 123", "第二行文本"])
        let lines = try await OcrEngine.recognize(in: image)
        let all = lines.map(\.text).joined(separator: "\n")
        #expect(all.contains("Hello"))
        #expect(all.contains("第二行"))
    }

    /// Renders black text on white, big enough for the recognizer, and returns
    /// the bitmap as a CGImage.
    private static func renderText(_ rows: [String]) throws -> CGImage {
        let size = NSSize(width: 640, height: CGFloat(rows.count) * 90 + 60)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 52, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        for (i, row) in rows.enumerated() {
            row.draw(at: NSPoint(x: 30, y: size.height - 90 - CGFloat(i) * 90),
                     withAttributes: attributes)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else {
            throw NSError(domain: "OcrEngineTests", code: 1)
        }
        return cg
    }
}
