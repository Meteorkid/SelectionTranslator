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
