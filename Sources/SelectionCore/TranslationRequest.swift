import Foundation

struct TranslationRequest: Sendable {
    let text: String
    let context: String
    let targetLanguage: String
    let model: String
    let apiBaseURL: String
    let apiKey: String
    let temperature: Double
    let maxOutputTokens: Int
    let documentContext: String
    let style: TranslationStyle
    let glossary: [GlossaryEntry]

    init(
        text: String,
        context: String,
        targetLanguage: String,
        model: String,
        apiBaseURL: String,
        apiKey: String,
        temperature: Double,
        maxOutputTokens: Int,
        documentContext: String = "",
        style: TranslationStyle = .natural,
        glossary: [GlossaryEntry] = []
    ) {
        self.text = text
        self.context = context
        self.targetLanguage = targetLanguage
        self.model = model
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.documentContext = documentContext
        self.style = style
        self.glossary = glossary
    }
}
