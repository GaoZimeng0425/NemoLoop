import CoreGraphics
import Foundation

/// One recognized text line, in Vision's own coordinate convention (normalized,
/// bottom-left origin) until sorted for reading.
struct OcrLine: Equatable {
    let text: String
    let boundingBox: CGRect
    /// BCP-47 language tag reported by recognition, e.g. "en-US"; nil if unknown.
    let language: String?
}

/// Pure post-processing over recognized lines — sorting into reading order,
/// translation gating, and clipboard joining. No Vision/AppKit, fully testable.
enum OcrTextProcessor {
    /// Vision returns observations unordered; read top-to-bottom, then
    /// left-to-right within a row. Rows are bands of similar y (small jitter
    /// from the recognizer must not split a visual line).
    static func sortedLines(_ lines: [OcrLine]) -> [OcrLine] {
        let byHeight = lines.map { ($0, max($0.boundingBox.height, 0.01)) }
        let ordered = byHeight.sorted { $0.0.boundingBox.minY > $1.0.boundingBox.minY }
        var rows: [[OcrLine]] = []
        var bandY: Double?
        for (line, height) in ordered {
            if let y = bandY, abs(line.boundingBox.minY - y) <= height * 0.8 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
                bandY = line.boundingBox.minY
            }
        }
        return rows.flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    /// Translation gating (v1): only confidently-English lines get en→zh;
    /// unknown languages are never guessed into a translation.
    static func shouldTranslate(_ line: OcrLine) -> Bool {
        line.language?.hasPrefix("en") == true
    }

    /// Joins the selected (text, isSelected) pairs with newlines for the clipboard.
    static func clipboardText(_ lines: [(text: String, isSelected: Bool)]) -> String {
        lines.filter(\.isSelected).map(\.text).joined(separator: "\n")
    }
}
