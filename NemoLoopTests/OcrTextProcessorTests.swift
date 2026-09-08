import CoreGraphics
import Testing
import Foundation
@testable import NemoLoop

struct OcrTextProcessorTests {
    // Vision boxes are normalized, bottom-left origin (y grows upward).
    private func line(_ text: String, _ x: Double, _ y: Double, _ lang: String? = nil) -> OcrLine {
        OcrLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.2, height: 0.05), language: lang)
    }

    @Test func sortedTopToBottomThenLeftToRight() {
        // A and B share a row band (A slightly lower in Vision space = higher on
        // screen); C sits clearly below. Reading order: A, B, C.
        let input = [
            line("B", 0.6, 0.80, "en-US"),
            line("C", 0.3, 0.30, "zh-Hans"),
            line("A", 0.2, 0.82, "en-US"),
        ]
        let sorted = OcrTextProcessor.sortedLines(input)
        #expect(sorted.map(\.text) == ["A", "B", "C"])
    }

    @Test func sortedRowsTolerateSmallJitter() {
        // Same visual row with a 0.04 y jitter must stay one row (x decides).
        let input = [
            line("right", 0.7, 0.50),
            line("left", 0.2, 0.54),
        ]
        #expect(OcrTextProcessor.sortedLines(input).map(\.text) == ["left", "right"])
    }

    @Test func onlyConfidentEnglishTranslates() {
        #expect(OcrTextProcessor.shouldTranslate(line("hello", 0, 0, "en-US")))
        #expect(OcrTextProcessor.shouldTranslate(line("hello", 0, 0, "en-GB")))
        #expect(!OcrTextProcessor.shouldTranslate(line("你好", 0, 0, "zh-Hans")))
        #expect(!OcrTextProcessor.shouldTranslate(line("bonjour", 0, 0, "fr-FR")))
        // Unknown language: never guess-translate.
        #expect(!OcrTextProcessor.shouldTranslate(line("ok", 0, 0, nil)))
    }

    @Test func clipboardJoinsSelectedWithNewlines() {
        let lines = [("first", true), ("skipped", false), ("second", true)]
        #expect(OcrTextProcessor.clipboardText(lines) == "first\nsecond")
        #expect(OcrTextProcessor.clipboardText([]) == "")
    }
}
