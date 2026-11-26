import Foundation

enum CaptureSource: String, Codable, Sendable {
    case accessibility
    case clipboard
    case ocr
    case input
    case browser

    var displayName: String {
        switch self {
        case .accessibility: return "取词"
        case .clipboard: return "剪贴板"
        case .ocr: return "OCR"
        case .input: return "输入"
        case .browser: return "浏览器"
        }
    }
}

struct CaptureResult: Codable, Sendable {
    let selectedText: String
    let context: String
    let appName: String
    let bundleID: String?
    let windowTitle: String?
    let source: CaptureSource
    let documentContext: String

    init(
        selectedText: String,
        context: String,
        appName: String,
        bundleID: String?,
        windowTitle: String?,
        source: CaptureSource,
        documentContext: String = ""
    ) {
        self.selectedText = selectedText
        self.context = context
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.source = source
        self.documentContext = documentContext
    }

    func withDocumentContext(_ text: String) -> CaptureResult {
        CaptureResult(
            selectedText: selectedText,
            context: context,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            source: source,
            documentContext: text
        )
    }
}
