import Foundation
import PDFKit

enum PDFTextExtractorError: LocalizedError {
    case unreadable
    case locked
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法打开这个 PDF。"
        case .locked: return "这个 PDF 有密码保护，请先解锁后再导入。"
        case .empty: return "PDF 里没有可提取的文字（可能是扫描件，请用截图 OCR）。"
        }
    }
}

enum PDFTextExtractor {
    static func extract(url: URL, maxCharacters: Int) throws -> String {
        guard maxCharacters > 0 else { return "" }
        guard let document = PDFDocument(url: url) else {
            throw PDFTextExtractorError.unreadable
        }
        guard !document.isLocked else {
            throw PDFTextExtractorError.locked
        }

        var pieces: [String] = []
        var total = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }
            let piece = text + "\n\n"
            pieces.append(piece)
            total += piece.count
            if total >= maxCharacters { break }
        }

        let joined = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else {
            throw PDFTextExtractorError.empty
        }
        return String(joined.prefix(maxCharacters))
    }
}
