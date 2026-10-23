import UIKit
import Vision

/// On-device OCR of a coffee-bag photo using Apple's Vision framework (Arabic +
/// English, no network). Returns the recognized text lines, most prominent first,
/// so the scan flow can search the catalog by what's printed on the bag.
enum BagTextRecognizer {
    static func recognize(_ imageData: Data) async -> [String] {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Prefer larger text (brand/product names sit on bigger boxes).
                let lines = observations
                    .sorted { $0.boundingBox.height > $1.boundingBox.height }
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 2 }
                // De-duplicate, keep order.
                var seen = Set<String>()
                let unique = lines.filter { seen.insert($0.lowercased()).inserted }
                continuation.resume(returning: Array(unique.prefix(8)))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ar", "en"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}
