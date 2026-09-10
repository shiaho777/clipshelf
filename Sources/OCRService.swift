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

enum OCRCandidateFilter {
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

extension OCRServiceProtocol {
    func recognizeText(in imageData: Data) async -> String? {
        await withCheckedContinuation { continuation in
            recognizeText(in: imageData) { result in
                continuation.resume(returning: result)
            }
        }
    }
}

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
