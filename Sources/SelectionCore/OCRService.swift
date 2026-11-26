import AppKit
import Foundation
@preconcurrency import Vision

enum OCRServiceError: LocalizedError {
    case cancelled
    case invalidImage
    case noText
    case processFailed(String)
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消截图。"
        case .invalidImage:
            return "截图不是有效图片。"
        case .noText:
            return "没有识别到文字。"
        case .processFailed(let message):
            return "截图失败：\(message)"
        case .visionFailed(let message):
            return "文字识别失败：\(message)"
        }
    }
}

private final class OCRProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func install(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if running?.isRunning == true {
            running?.terminate()
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum OCRService {
    /// Opens the native interactive selection UI, then runs Apple Vision OCR.
    /// The child process is terminated when the surrounding task is cancelled,
    /// otherwise a pending screencapture overlay would outlive the panel.
    static func captureInteractiveText() async throws -> String {
        let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("selectiontranslator-ocr-\(UUID().uuidString).png")
        let box = OCRProcessBox()

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: temporaryURL) }

                if box.isCancelled { throw CancellationError() }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", temporaryURL.path]
                box.install(process)

                do {
                    try process.run()
                } catch {
                    box.clear()
                    throw OCRServiceError.processFailed(error.localizedDescription)
                }
                process.waitUntilExit()
                box.clear()

                if box.isCancelled { throw CancellationError() }
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: temporaryURL.path) else {
                    throw OCRServiceError.cancelled
                }
                guard let image = NSImage(contentsOf: temporaryURL) else {
                    throw OCRServiceError.invalidImage
                }
                return try await recognize(image: image)
            }.value
        } onCancel: {
            box.cancel()
        }
    }

    /// Recognizes text from an existing image (used by clipboard image OCR too).
    static func recognize(image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRServiceError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            "en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR",
            "fr-FR", "de-DE", "es-ES", "pt-BR", "ru-RU", "it-IT", "ar-SA"
        ]

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
        } catch {
            throw OCRServiceError.visionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        let sorted = observations.sorted { lhs, rhs in
            let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDelta > 0.025 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        // Use the actual line height to decide paragraph breaks. A fixed
        // threshold inserts blank lines between ordinary single-spaced lines.
        let lineHeights = sorted.map(\.boundingBox.height).sorted()
        let medianLineHeight = lineHeights.isEmpty
            ? 0.03
            : lineHeights[lineHeights.count / 2]
        let paragraphGap = max(0.03, medianLineHeight * 1.7)

        var lines: [String] = []
        var lastMidY: CGFloat?
        for observation in sorted {
            guard let candidate = observation.topCandidates(1).first else { continue }
            if let lastMidY, lastMidY - observation.boundingBox.midY > paragraphGap {
                lines.append("")
            }
            lines.append(candidate.string)
            lastMidY = observation.boundingBox.midY
        }

        let text = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OCRServiceError.noText }
        return text
    }
}
