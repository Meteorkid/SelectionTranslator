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

    /// Starts the capture process atomically with respect to cancel. If the
    /// process were installed first and started later, a cancel in between
    /// would see `isRunning == false`, skip termination, and leave the
    /// interactive overlay alive after the task had already been cancelled.
    func start(_ process: Process) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        do {
            try process.run()
        } catch {
            self.process = nil
            throw error
        }
        return true
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
    private static let activeLock = NSLock()
    private static var activeCaptures: [ObjectIdentifier: OCRProcessBox] = [:]

    /// Terminate any interactive screencapture child when the app is quitting.
    /// Otherwise the overlay can outlive the parent process and keep a
    /// temporary screenshot on disk until the user dismisses it.
    static func cancelActiveCaptures() {
        activeLock.lock()
        let boxes = Array(activeCaptures.values)
        activeCaptures.removeAll()
        activeLock.unlock()
        boxes.forEach { $0.cancel() }
    }

    private static func register(_ box: OCRProcessBox) {
        activeLock.lock()
        activeCaptures[ObjectIdentifier(box)] = box
        activeLock.unlock()
    }

    private static func unregister(_ box: OCRProcessBox) {
        activeLock.lock()
        activeCaptures.removeValue(forKey: ObjectIdentifier(box))
        activeLock.unlock()
    }

    /// Opens the native interactive selection UI, then runs Apple Vision OCR.
    /// The child process is terminated when the surrounding task is cancelled,
    /// otherwise a pending screencapture overlay would outlive the panel.
    static func captureInteractiveText() async throws -> String {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("selectiontranslator-ocr-\(UUID().uuidString)", isDirectory: true)
        let temporaryURL = temporaryDirectory.appendingPathComponent("capture.png")
        let box = OCRProcessBox()
        register(box)
        defer { unregister(box) }

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

                if box.isCancelled { throw CancellationError() }
                do {
                    try FileManager.default.createDirectory(
                        at: temporaryDirectory,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                } catch {
                    throw OCRServiceError.processFailed(error.localizedDescription)
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", temporaryURL.path]
                do {
                    guard try box.start(process) else {
                        throw CancellationError()
                    }
                } catch let error as CancellationError {
                    throw error
                } catch {
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
        // Vision is synchronous and can take seconds on a large screenshot.
        // Keep it off the main actor so clipboard OCR never freezes the UI.
        return try await Task.detached(priority: .userInitiated) {
            try recognize(cgImage: cgImage)
        }.value
    }

    private static func recognize(cgImage: CGImage) throws -> String {
        let originalPass = OCRPassVariant(
            image: cgImage,
            usesLanguageCorrection: true,
            minimumTextHeight: 0
        )
        var best: OCRQuality?
        var lastError: Error?

        func run(_ variant: OCRPassVariant) {
            do {
                let quality = try recognizePass(variant)
                guard !quality.text.isEmpty else { return }
                if best == nil || quality.score > best!.score {
                    best = quality
                }
            } catch {
                lastError = error
            }
        }

        // First pass: the untouched image. If it is already reliable, stop;
        // otherwise retry with contrast/sharpness and, if needed, inversion.
        run(originalPass)
        if best?.isReliable != true,
           let enhanced = OCRImageEnhancer.enhanced(from: cgImage) {
            run(OCRPassVariant(
                image: enhanced,
                usesLanguageCorrection: false,
                minimumTextHeight: 0.002
            ))
        }
        if best?.isReliable != true,
           let inverted = OCRImageEnhancer.enhanced(from: cgImage, inverted: true) {
            run(OCRPassVariant(
                image: inverted,
                usesLanguageCorrection: false,
                minimumTextHeight: 0.002
            ))
        }

        if let best {
            return String(best.text.prefix(8_000))
        }
        if let lastError {
            throw OCRServiceError.visionFailed(lastError.localizedDescription)
        }
        throw OCRServiceError.noText
    }
}


private struct OCRPassVariant {
    let image: CGImage
    let usesLanguageCorrection: Bool
    let minimumTextHeight: Float
}

private extension OCRService {
    static func recognizePass(_ variant: OCRPassVariant) throws -> OCRQuality {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = variant.usesLanguageCorrection
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = variant.minimumTextHeight
        // A fixed first language gives English lines full-width punctuation
        // when the screenshot contains Chinese. Let Vision detect each line.
        request.recognitionLanguages = [
            "zh-Hans", "en-US", "zh-Hant", "ja-JP", "ko-KR",
            "fr-FR", "de-DE", "es-ES", "pt-BR", "ru-RU", "it-IT", "ar-SA"
        ]

        let handler = VNImageRequestHandler(cgImage: variant.image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRServiceError.visionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        let lines: [RecognizedLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision measures from the bottom-left; the layout reads top-down.
            return RecognizedLine(
                text: candidate.string,
                frame: CGRect(
                    x: box.minX,
                    y: 1 - box.maxY,
                    width: box.width,
                    height: box.height
                )
            )
        }
        let text = OCRTextLayout.text(from: lines) ?? ""
        let confidences = observations
            .compactMap { $0.topCandidates(1).first?.confidence }
            .map(Double.init)
        let averageConfidence = confidences.isEmpty
            ? 0
            : confidences.reduce(0, +) / Double(confidences.count)
        return OCRQuality(
            text: text,
            averageConfidence: averageConfidence,
            lineCount: lines.count
        )
    }
}
