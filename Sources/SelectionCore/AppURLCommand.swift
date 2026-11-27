import Foundation

struct BrowserTranslationRequest: Equatable, Sendable {
    let text: String
    let context: String
    let appName: String
    let title: String?
    let documentContext: String
}

enum AppURLCommand: Equatable, Sendable {
    case translate(BrowserTranslationRequest)
    case clipboard
    case input
    case ocr
    case silentOCR
    case library
    case settings
    case unknown(String)

    /// Every known URL command can read local data, trigger capture, or open
    /// a window. Only the unknown fallback is inert, so only that case is
    /// allowed through without a verified external caller.
    var requiresExternalCallerVerification: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// The existing `ExternalURLGate` was designed for text payloads. For
    /// commands without a text body, use one token so they still share the
    /// same per-minute request budget.
    var externalRateLimitCharacters: Int {
        switch self {
        case .translate(let request):
            return max(1, request.text.count)
        case .clipboard, .input, .ocr, .silentOCR, .library, .settings:
            return 1
        case .unknown:
            return 0
        }
    }
}

enum AppURLParser {
    static let scheme = "selectiontranslator"

    static func parse(_ url: URL) -> AppURLCommand? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let rawAction = components.host ?? components.path
        let action = rawAction
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        // URLSearchParams encodes spaces as "+", while a literal plus is "%2B".
        // Replace raw "+" before URLComponents decodes it, so a real plus survives.
        var fixedComponents = components
        if let rawQuery = components.percentEncodedQuery {
            fixedComponents.percentEncodedQuery = rawQuery.replacingOccurrences(of: "+", with: "%20")
        }

        var items: [String: String] = [:]
        for item in fixedComponents.queryItems ?? [] {
            guard let value = item.value else { continue }
            items[item.name] = value
        }

        switch action {
        case "translate":
            return .translate(
                BrowserTranslationRequest(
                    text: String((items["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000)),
                    context: String((items["context"] ?? "").prefix(3_000)),
                    appName: items["app"] ?? "浏览器",
                    title: items["title"].flatMap { $0.isEmpty ? nil : $0 },
                    documentContext: String((items["document"] ?? "").prefix(6_000))
                )
            )
        case "clipboard":
            return .clipboard
        case "input":
            return .input
        case "ocr":
            return .ocr
        case "silent-ocr", "silentocr":
            return .silentOCR
        case "library":
            return .library
        case "settings":
            return .settings
        default:
            return .unknown(action)
        }
    }
}
