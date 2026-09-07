import Foundation
import Vision
import os

protocol OCRServiceProtocol {
    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void)
}

final class VisionOCRService: OCRServiceProtocol {
    static let shared = VisionOCRService()
    private let queue = DispatchQueue(label: "OCRService", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "OCR")

    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        queue.async { [logger] in
            guard let cgImage = Self.createCGImage(from: imageData) else {
                logger.debug("Failed to create CGImage for OCR")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    logger.error("OCR failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let candidates = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first }
                    .map { (string: $0.string, confidence: $0.confidence) } ?? []
                DispatchQueue.main.async {
                    completion(OCRCandidateFilter.joinedText(from: candidates))
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en", "zh-Hans", "zh-Hant"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logger.error("VNImageRequestHandler failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private static func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Candidate Confidence Filter

/// Joins Vision's top candidates into the stored OCR string, dropping
/// observations below a confidence floor. Stylized UI text (art fonts in
/// music players, game HUDs, decorative glyphs) recognizes at low confidence
/// and used to land in `ocrText` as glyph soup — polluting not just the list
/// row but search and preview too, since the stored text was never filtered.
/// Pure function over (string, confidence) tuples so it is unit-testable:
/// VNRecognizedTextObservation cannot be constructed in tests.
enum OCRCandidateFilter {
    /// Observations below this Vision confidence are dropped. 0.5 keeps clear
    /// rendered text (typically 0.8–1.0) while cutting art-font noise.
    static let minimumConfidence: Float = 0.5

    static func joinedText(from candidates: [(string: String, confidence: Float)]) -> String? {
        let text = candidates
            .filter { $0.confidence >= minimumConfidence }
            .map(\.string)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - Async/Await Extension

extension OCRServiceProtocol {
    /// Async wrapper around the callback-based `recognizeText(in:completion:)`.
    func recognizeText(in imageData: Data) async -> String? {
        await withCheckedContinuation { continuation in
            recognizeText(in: imageData) { result in
                continuation.resume(returning: result)
            }
        }
    }
}

// MARK: - OCR Text Quality Gate

/// Decides whether an image's OCR text is worth showing in list rows.
/// Stylized UI text (music players, game HUDs, art fonts) OCRs into glyph
/// soup like "e13· = 4 140₿ +J" — technically tokens, practically noise.
/// A token only counts as a word when it is clean letters/digits (a few
/// interior marks like ":" "/" "." allowed so times and paths qualify);
/// rows fall back to the plain "[Image]" label below the word threshold.
/// Display-only: the full OCR text stays stored for search and preview.
enum OCRTextQuality {
    private static let allowedInteriorMarks: Set<Character> = [":", "/", ".", "-", "'", "@", "_"]

    static func usableText(from ocrText: String?, minWords: Int = 3) -> String? {
        guard let text = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        var words = 0
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            var hasLetter = false
            var digits = 0
            var clean = true
            for ch in token {
                if ch.isLetter { hasLetter = true }
                else if ch.isNumber { digits += 1 }
                else if !allowedInteriorMarks.contains(ch) { clean = false; break }
            }
            if clean && (hasLetter || digits >= 2) { words += 1 }
            if words >= minWords { return text }
        }
        return nil
    }
}
