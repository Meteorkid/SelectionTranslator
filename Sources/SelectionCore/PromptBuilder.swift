import Foundation

enum PromptBuilder {
    static func translationMessages(for request: TranslationRequest) -> [[String: String]] {
        let target = LanguageCatalog.promptName(for: request.targetLanguage)
        let system = """
        You are a precise bilingual reading assistant. Use the surrounding context only to resolve ambiguity, pronouns, terminology, and tone. Never translate or repeat the context itself. Output only the translation of the selection. Keep the original formatting, line breaks, and markdown. If the selection is a single word, give the meaning in this specific context first, then common senses, part of speech, and one short example; keep it compact. If the selection is a sentence, produce a natural translation, not a word-by-word gloss. If the selection is code, preserve identifiers and explain only what is ambiguous. \(request.style.promptInstruction)
        """

        var user = """
        <context>
        \(request.context)
        </context>

        <selection>
        \(request.text)
        </selection>

        Translate the content inside <selection> into \(target).
        Do not translate the content inside <context>; use it only as background.
        If the selection is already in \(target), explain it in \(target) instead.
        """

        let glossary = request.glossary
            .filter(\.isValid)
            .map { "- \($0.term.trimmingCharacters(in: .whitespacesAndNewlines)) => \($0.translation.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")

        if !glossary.isEmpty {
            user = """
            <glossary>
            \(glossary)
            </glossary>

            """ + user + """


            Apply the glossary exactly when the corresponding term appears in the selection.
            Do not invent glossary entries or apply them to unrelated text.
            """
        }

        let document = request.documentContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !document.isEmpty {
            user = """
            <document>
            \(document)
            </document>

            """ + user + """


            The <document> block is the broader article or document the selection came from.
            Use it to resolve terminology, named entities, and the author's argument.
            Do not quote or translate the whole document; only translate <selection>.
            """
        }

        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }
}
