import AppKit
import NaturalLanguage
import Vision

/// Thin wrapper over the system OCR engine (Vision's text recognizer — the same
/// engine behind Live Text). Offline, no permission needed for images we already
/// hold in memory.
enum OcrEngine {
    static let recognitionLanguages = ["zh-Hans", "en-US"]

    static func recognize(in image: CGImage) async throws -> [OcrLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let lines: [OcrLine] = observations.compactMap { (observation) -> OcrLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision doesn't report a language here — detect per line with NL.
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(candidate.string)
            return OcrLine(text: candidate.string,
                           boundingBox: observation.boundingBox,
                           language: recognizer.dominantLanguage?.rawValue)
        }
        return lines
    }
}
