import AppKit
import Vision

public struct OCRResult {
    public let text: String
    public let lineCount: Int
    public let characterCount: Int

    public var summary: String {
        if lineCount <= 1 {
            return "Copied \(characterCount) character\(characterCount == 1 ? "" : "s") to clipboard"
        } else {
            return "Copied \(lineCount) lines (\(characterCount) chars) to clipboard"
        }
    }
}

public class TextRecognitionService {
    public static let shared = TextRecognitionService()

    private init() {}

    /// Performs on-device Vision OCR on the provided CGImage, copies recognized text to clipboard, and returns result.
    public func recognizeAndCopyText(from cgImage: CGImage, completion: @escaping (OCRResult?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Extract the highest confidence candidate for each recognized text line
            let recognizedLines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            let fullText = recognizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !fullText.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Copy directly to macOS clipboard
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(fullText, forType: .string)

                let result = OCRResult(
                    text: fullText,
                    lineCount: recognizedLines.count,
                    characterCount: fullText.count
                )
                completion(result)
            }
        }

        // Apple Silicon Neural Engine Acceleration & Maximum Accuracy
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("⚠️ TextRecognitionService error: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
