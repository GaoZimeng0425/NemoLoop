import AppKit
import Translation

/// On-device en→zh translation for recognized lines, via the system Translation
/// framework (offline). Every failure mode degrades to "no translation" — the
/// original text is always preserved and shown.
enum OcrTranslationService {
    private static let source = Locale.Language(identifier: "en")
    private static let target = Locale.Language(identifier: "zh-Hans")

    /// Returns one translation per input line: nil = no translation available
    /// (unsupported pair, not downloaded, or session error).
    static func translateToChinese(_ lines: [String]) async -> [String?] {
        let none = [String?](repeating: nil, count: lines.count)
        guard !lines.isEmpty else { return none }
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        guard status == .installed || status == .supported else { return none }
        do {
            let session = try await TranslationSession(installedSource: source, target: target)
            let requests = lines.map { TranslationSession.Request(sourceText: $0) }
            var results: [String?] = none
            for try await response in session.translate(batch: requests) {
                if let idx = lines.firstIndex(of: response.sourceText), results[idx] == nil {
                    results[idx] = response.targetText
                }
            }
            return results
        } catch {
            NSLog("NemoLoop OCR: translation unavailable (\(error.localizedDescription))")
            return none
        }
    }
}
