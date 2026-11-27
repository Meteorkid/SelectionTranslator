import Foundation

// MARK: - Hot keys

enum HotKeyKey: UInt32, CaseIterable, Codable, Sendable {
    case a = 0
    case s = 1
    case d = 2
    case f = 3
    case h = 4
    case g = 5
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case q = 12
    case w = 13
    case e = 14
    case r = 15
    case y = 16
    case t = 17
    case one = 18
    case two = 19
    case three = 20
    case four = 21
    case six = 22
    case five = 23
    case equal = 24
    case nine = 25
    case seven = 26
    case minus = 27
    case eight = 28
    case zero = 29
    case rightBracket = 30
    case o = 31
    case u = 32
    case leftBracket = 33
    case i = 34
    case p = 35
    case l = 37
    case j = 38
    case k = 40
    case semicolon = 41
    case backslash = 42
    case comma = 43
    case slash = 44
    case period = 47
    case backtick = 50

    var displayName: String {
        switch self {
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        case .f: return "F"
        case .h: return "H"
        case .g: return "G"
        case .z: return "Z"
        case .x: return "X"
        case .c: return "C"
        case .v: return "V"
        case .b: return "B"
        case .q: return "Q"
        case .w: return "W"
        case .e: return "E"
        case .r: return "R"
        case .y: return "Y"
        case .t: return "T"
        case .o: return "O"
        case .u: return "U"
        case .i: return "I"
        case .p: return "P"
        case .l: return "L"
        case .j: return "J"
        case .k: return "K"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .zero: return "0"
        case .equal: return "="
        case .minus: return "-"
        case .rightBracket: return "]"
        case .leftBracket: return "["
        case .semicolon: return ";"
        case .backslash: return "\\"
        case .comma: return ","
        case .slash: return "/"
        case .period: return "."
        case .backtick: return "`"
        }
    }
}

struct HotKeyBinding: Codable, Equatable, Sendable {
    var key: HotKeyKey = .d
    var command: Bool = false
    var option: Bool = true
    var shift: Bool = false
    var control: Bool = false

    var hasModifier: Bool { command || option || shift || control }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if command { value |= UInt32(0x0100) }
        if shift { value |= UInt32(0x0200) }
        // Carbon controlKey is bit 12 (0x1000); 0x0400 is alphaLock.
        if control { value |= UInt32(0x1000) }
        if option { value |= UInt32(0x0800) }
        return value
    }

    /// Human-readable shortcut, e.g. ⌥D.
    var display: String {
        var parts = ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts + key.displayName
    }

    init(
        key: HotKeyKey = .d,
        command: Bool = false,
        option: Bool = true,
        shift: Bool = false,
        control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(HotKeyKey.self, forKey: .key) ?? .d
        command = try container.decodeIfPresent(Bool.self, forKey: .command) ?? false
        option = try container.decodeIfPresent(Bool.self, forKey: .option) ?? true
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        control = try container.decodeIfPresent(Bool.self, forKey: .control) ?? false
    }
}

struct HotKeySettings: Codable, Equatable, Sendable {
    var selection = HotKeyBinding(key: .d, option: true)
    var clipboard = HotKeyBinding(key: .v, option: true)
    var input = HotKeyBinding(key: .a, option: true)
    var ocr = HotKeyBinding(key: .o, option: true)
    var silentOCR = HotKeyBinding(key: .s, option: true, shift: true)
    var library = HotKeyBinding(key: .l, option: true)
    var settings = HotKeyBinding(key: .comma, option: true)

    static let `default` = HotKeySettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decodeIfPresent(HotKeyBinding.self, forKey: .selection) ?? Self.default.selection
        clipboard = try container.decodeIfPresent(HotKeyBinding.self, forKey: .clipboard) ?? Self.default.clipboard
        input = try container.decodeIfPresent(HotKeyBinding.self, forKey: .input) ?? Self.default.input
        ocr = try container.decodeIfPresent(HotKeyBinding.self, forKey: .ocr) ?? Self.default.ocr
        silentOCR = try container.decodeIfPresent(HotKeyBinding.self, forKey: .silentOCR) ?? Self.default.silentOCR
        library = try container.decodeIfPresent(HotKeyBinding.self, forKey: .library) ?? Self.default.library
        settings = try container.decodeIfPresent(HotKeyBinding.self, forKey: .settings) ?? Self.default.settings
    }
}

enum HotKeyAction: UInt32, CaseIterable, Sendable {
    case selection = 1
    case clipboard = 2
    case input = 3
    case ocr = 4
    case silentOCR = 7
    case library = 5
    case settings = 6

    var title: String {
        switch self {
        case .selection: return "划词翻译"
        case .clipboard: return "剪贴板翻译"
        case .input: return "输入翻译"
        case .ocr: return "截图 OCR"
        case .silentOCR: return "静默 OCR"
        case .library: return "历史与生词本"
        case .settings: return "打开设置"
        }
    }
}

extension HotKeySettings {
    func binding(for action: HotKeyAction) -> HotKeyBinding {
        switch action {
        case .selection: return selection
        case .clipboard: return clipboard
        case .input: return input
        case .ocr: return ocr
        case .silentOCR: return silentOCR
        case .library: return library
        case .settings: return settings
        }
    }

    var allBindings: [HotKeyAction: HotKeyBinding] {
        Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, binding(for: $0)) })
    }
}

// MARK: - Languages

struct LanguageOption: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let promptName: String
    let systemIdentifier: String

    init(displayName: String, promptName: String, systemIdentifier: String) {
        id = displayName
        self.displayName = displayName
        self.promptName = promptName
        self.systemIdentifier = systemIdentifier
    }
}

enum LanguageCatalog {
    static let targets: [LanguageOption] = [
        .init(displayName: "简体中文", promptName: "Simplified Chinese", systemIdentifier: "zh-Hans"),
        .init(displayName: "繁體中文", promptName: "Traditional Chinese", systemIdentifier: "zh-Hant"),
        .init(displayName: "English", promptName: "English", systemIdentifier: "en"),
        .init(displayName: "日本語", promptName: "Japanese", systemIdentifier: "ja"),
        .init(displayName: "한국어", promptName: "Korean", systemIdentifier: "ko"),
        .init(displayName: "Français", promptName: "French", systemIdentifier: "fr"),
        .init(displayName: "Deutsch", promptName: "German", systemIdentifier: "de"),
        .init(displayName: "Español", promptName: "Spanish", systemIdentifier: "es"),
        .init(displayName: "Português", promptName: "Portuguese", systemIdentifier: "pt"),
        .init(displayName: "Русский", promptName: "Russian", systemIdentifier: "ru"),
        .init(displayName: "Italiano", promptName: "Italian", systemIdentifier: "it"),
        .init(displayName: "العربية", promptName: "Arabic", systemIdentifier: "ar"),
        .init(displayName: "Nederlands", promptName: "Dutch", systemIdentifier: "nl"),
        .init(displayName: "Svenska", promptName: "Swedish", systemIdentifier: "sv"),
        .init(displayName: "Norsk Bokmål", promptName: "Norwegian Bokmål", systemIdentifier: "nb"),
        .init(displayName: "Dansk", promptName: "Danish", systemIdentifier: "da"),
        .init(displayName: "Suomi", promptName: "Finnish", systemIdentifier: "fi"),
        .init(displayName: "Polski", promptName: "Polish", systemIdentifier: "pl"),
        .init(displayName: "Čeština", promptName: "Czech", systemIdentifier: "cs"),
        .init(displayName: "Slovenčina", promptName: "Slovak", systemIdentifier: "sk"),
        .init(displayName: "Magyar", promptName: "Hungarian", systemIdentifier: "hu"),
        .init(displayName: "Română", promptName: "Romanian", systemIdentifier: "ro"),
        .init(displayName: "Български", promptName: "Bulgarian", systemIdentifier: "bg"),
        .init(displayName: "Ελληνικά", promptName: "Greek", systemIdentifier: "el"),
        .init(displayName: "Türkçe", promptName: "Turkish", systemIdentifier: "tr"),
        .init(displayName: "עברית", promptName: "Hebrew", systemIdentifier: "he"),
        .init(displayName: "हिन्दी", promptName: "Hindi", systemIdentifier: "hi"),
        .init(displayName: "ไทย", promptName: "Thai", systemIdentifier: "th"),
        .init(displayName: "Tiếng Việt", promptName: "Vietnamese", systemIdentifier: "vi"),
        .init(displayName: "Bahasa Indonesia", promptName: "Indonesian", systemIdentifier: "id"),
        .init(displayName: "Bahasa Melayu", promptName: "Malay", systemIdentifier: "ms"),
        .init(displayName: "Filipino", promptName: "Filipino", systemIdentifier: "fil"),
        .init(displayName: "Kiswahili", promptName: "Swahili", systemIdentifier: "sw"),
        .init(displayName: "Українська", promptName: "Ukrainian", systemIdentifier: "uk"),
        .init(displayName: "Српски", promptName: "Serbian", systemIdentifier: "sr"),
        .init(displayName: "Hrvatski", promptName: "Croatian", systemIdentifier: "hr"),
        .init(displayName: "Lietuvių", promptName: "Lithuanian", systemIdentifier: "lt"),
        .init(displayName: "Latviešu", promptName: "Latvian", systemIdentifier: "lv"),
        .init(displayName: "Eesti", promptName: "Estonian", systemIdentifier: "et"),
        .init(displayName: "Íslenska", promptName: "Icelandic", systemIdentifier: "is"),
        .init(displayName: "Català", promptName: "Catalan", systemIdentifier: "ca"),
        .init(displayName: "Euskara", promptName: "Basque", systemIdentifier: "eu"),
        .init(displayName: "Galego", promptName: "Galician", systemIdentifier: "gl"),
        .init(displayName: "বাংলা", promptName: "Bengali", systemIdentifier: "bn"),
        .init(displayName: "தமிழ்", promptName: "Tamil", systemIdentifier: "ta"),
        .init(displayName: "తెలుగు", promptName: "Telugu", systemIdentifier: "te"),
        .init(displayName: "മലയാളം", promptName: "Malayalam", systemIdentifier: "ml"),
        .init(displayName: "ಕನ್ನಡ", promptName: "Kannada", systemIdentifier: "kn"),
        .init(displayName: "मराठी", promptName: "Marathi", systemIdentifier: "mr"),
        .init(displayName: "ગુજરાતી", promptName: "Gujarati", systemIdentifier: "gu"),
        .init(displayName: "ਪੰਜਾਬੀ", promptName: "Punjabi", systemIdentifier: "pa"),
        .init(displayName: "ລາວ", promptName: "Lao", systemIdentifier: "lo")
    ]

    static func option(named name: String) -> LanguageOption {
        targets.first { $0.displayName == name } ?? targets[0]
    }

    static func promptName(for name: String) -> String {
        option(named: name).promptName
    }

    static func systemIdentifier(for name: String) -> String {
        option(named: name).systemIdentifier
    }
}

// MARK: - Settings

enum AppAppearance: String, CaseIterable, Codable, Hashable, Sendable {
    case native
    case liquidGlass
}

enum TranslationStyle: String, CaseIterable, Codable, Sendable {
    case natural
    case faithful
    case academic
    case technical
    case concise

    var title: String {
        switch self {
        case .natural: return "自然"
        case .faithful: return "忠实"
        case .academic: return "学术"
        case .technical: return "技术"
        case .concise: return "简洁"
        }
    }

    var promptInstruction: String {
        switch self {
        case .natural:
            return "Prefer natural, idiomatic target-language phrasing while preserving the author's meaning."
        case .faithful:
            return "Stay close to the source structure and wording; do not add interpretation."
        case .academic:
            return "Use precise academic register, keep terminology consistent, and preserve hedging and citations."
        case .technical:
            return "Use precise technical terminology; preserve identifiers, API names, and code exactly."
        case .concise:
            return "Be compact and direct; remove redundancy without dropping essential meaning."
        }
    }
}

struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var term: String = ""
    var translation: String = ""

    var isValid: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var appearance: AppAppearance = .native
    var apiBaseURL: String = "https://api.deepseek.com/v1"
    var model: String = "deepseek-chat"
    var providerName: String = "DeepSeek"
    var targetLanguage: String = "简体中文"
    var translationStyle: TranslationStyle = .natural
    var glossary: [GlossaryEntry] = []
    var contextLength: Int = 1600
    var useClipboardFallback: Bool = true
    var temperature: Double = 0.2
    var maxOutputTokens: Int = 1024
    var enableOCR: Bool = true
    var enableTTS: Bool = true
    var useAppleDictionary: Bool = true
    var enableMouseSelection: Bool = true
    var mouseHoverTranslate: Bool = true
    var autoTranslateOnSelection: Bool = false
    var excludedBundleIDs: [String] = []
    var useDocumentContext: Bool = true
    var documentContextMaxChars: Int = 6000
    var ankiURL: String = "http://127.0.0.1:8765"
    var ankiDeck: String = "Default"
    var ankiModel: String = "Basic"
    var ankiTags: String = "SelectionTranslator"
    var hotkeys = HotKeySettings.default

    func isAppExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    /// Ollama / LM Studio 等本地服务通常不校验 API Key。
    var isLocalProvider: Bool {
        EndpointURL.isLocal(apiBaseURL)
    }

    var isUsableWithoutKey: Bool {
        isLocalProvider
    }

    init() {}

    static func inferProviderName(from baseURL: String) -> String {
        let normalized = baseURL.lowercased()
        if normalized.contains("11434") { return "Ollama" }
        if normalized.contains("1234") { return "LM Studio" }
        if normalized.contains("api.deepseek.com") { return "DeepSeek" }
        if normalized.contains("api.openai.com") { return "OpenAI" }
        return "自定义服务"
    }

    enum CodingKeys: String, CodingKey {
        case appearance
        case apiBaseURL
        case model
        case providerName
        case targetLanguage
        case translationStyle
        case glossary
        case contextLength
        case useClipboardFallback
        case temperature
        case maxOutputTokens
        case enableOCR
        case enableTTS
        case useAppleDictionary
        case enableMouseSelection
        case mouseHoverTranslate
        case autoTranslateOnSelection
        case excludedBundleIDs
        case useDocumentContext
        case documentContextMaxChars
        case ankiURL
        case ankiDeck
        case ankiModel
        case ankiTags
        case hotkeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? defaults.appearance
        apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? defaults.apiBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? defaults.targetLanguage
        translationStyle = try container.decodeIfPresent(TranslationStyle.self, forKey: .translationStyle) ?? defaults.translationStyle
        glossary = try container.decodeIfPresent([GlossaryEntry].self, forKey: .glossary) ?? defaults.glossary
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength) ?? defaults.contextLength
        useClipboardFallback = try container.decodeIfPresent(Bool.self, forKey: .useClipboardFallback) ?? defaults.useClipboardFallback
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? defaults.maxOutputTokens
        enableOCR = try container.decodeIfPresent(Bool.self, forKey: .enableOCR) ?? defaults.enableOCR
        enableTTS = try container.decodeIfPresent(Bool.self, forKey: .enableTTS) ?? defaults.enableTTS
        useAppleDictionary = try container.decodeIfPresent(Bool.self, forKey: .useAppleDictionary) ?? defaults.useAppleDictionary
        enableMouseSelection = try container.decodeIfPresent(Bool.self, forKey: .enableMouseSelection) ?? defaults.enableMouseSelection
        mouseHoverTranslate = try container.decodeIfPresent(Bool.self, forKey: .mouseHoverTranslate) ?? defaults.mouseHoverTranslate
        autoTranslateOnSelection = try container.decodeIfPresent(Bool.self, forKey: .autoTranslateOnSelection) ?? defaults.autoTranslateOnSelection
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? defaults.excludedBundleIDs
        useDocumentContext = try container.decodeIfPresent(Bool.self, forKey: .useDocumentContext) ?? defaults.useDocumentContext
        documentContextMaxChars = try container.decodeIfPresent(Int.self, forKey: .documentContextMaxChars) ?? defaults.documentContextMaxChars
        ankiURL = try container.decodeIfPresent(String.self, forKey: .ankiURL) ?? defaults.ankiURL
        ankiDeck = try container.decodeIfPresent(String.self, forKey: .ankiDeck) ?? defaults.ankiDeck
        ankiModel = try container.decodeIfPresent(String.self, forKey: .ankiModel) ?? defaults.ankiModel
        ankiTags = try container.decodeIfPresent(String.self, forKey: .ankiTags) ?? defaults.ankiTags
        hotkeys = try container.decodeIfPresent(HotKeySettings.self, forKey: .hotkeys) ?? defaults.hotkeys

        // Older settings only stored DeepSeek's name while pointing at a local URL.
        // Keep the visible provider label honest after migrating that config.
        if providerName.isEmpty
            || (providerName == "DeepSeek" && !apiBaseURL.contains("api.deepseek.com")) {
            providerName = Self.inferProviderName(from: apiBaseURL)
        }
    }
}


// MARK: - Endpoint URLs

enum EndpointURL {
    /// Accept common hand-typed endpoints without a scheme. Loopback,
    /// link-local and private-network addresses default to HTTP because that
    /// is what Ollama, LM Studio and AnkiConnect expose; public hosts default
    /// to HTTPS so an API key is never sent in cleartext by accident.
    static func normalized(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }
        if !value.contains("://") {
            value = (isLocalHost(value) ? "http://" : "https://") + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func normalizedBase(_ raw: String) -> String {
        var value = normalized(raw)
        if value.hasSuffix("/chat/completions") {
            value.removeLast("/chat/completions".count)
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func isLocal(_ raw: String) -> Bool {
        isLocalHost(normalized(raw))
    }

    /// Public endpoints must use HTTPS; loopback and private-network addresses
    /// may use HTTP because that is what local model servers expose.
    static func isPermittedTransport(_ raw: String) -> Bool {
        let value = normalized(raw)
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "https" || (scheme == "http" && isLocal(value))
    }

    private static func isLocalHost(_ normalized: String) -> Bool {
        var candidate = normalized
        if !candidate.contains("://") { candidate = "http://" + candidate }
        guard let host = URL(string: candidate)?.host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" || host == "0.0.0.0" { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }
        if host.hasPrefix("172."),
           let second = host.split(separator: ".").dropFirst().first,
           let number = Int(second),
           (16...31).contains(number) {
            return true
        }
        return host.hasSuffix(".local")
    }
}
