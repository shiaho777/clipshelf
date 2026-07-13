import Foundation
import Vision
import os

protocol OCRServiceProtocol {
    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void)
}

final class VisionOCRService: OCRServiceProtocol {
    static let shared = VisionOCRService()
    private let queue = DispatchQueue(label: "OCRService", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "OCR")

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
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let result = (text?.isEmpty ?? true) ? nil : text
                DispatchQueue.main.async { completion(result) }
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
