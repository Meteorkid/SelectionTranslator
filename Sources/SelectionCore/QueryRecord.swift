import Foundation

struct QueryRecord: Identifiable, Codable, Equatable, Sendable {
    var id: Int64
    var accountID: UUID
    var createdAt: Date
    var sourceText: String
    var translatedText: String
    var context: String
    var appName: String
    var bundleID: String?
    var sourceKind: String
    var engine: String
    var targetLanguage: String
    var isFavorite: Bool

    init(
        id: Int64 = 0,
        accountID: UUID,
        createdAt: Date = Date(),
        sourceText: String,
        translatedText: String,
        context: String,
        appName: String,
        bundleID: String? = nil,
        sourceKind: String,
        engine: String,
        targetLanguage: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.context = context
        self.appName = appName
        self.bundleID = bundleID
        self.sourceKind = sourceKind
        self.engine = engine
        self.targetLanguage = targetLanguage
        self.isFavorite = isFavorite
    }
}

struct HistoryStats: Equatable, Sendable {
    var total: Int = 0
    var favorites: Int = 0
    var characters: Int = 0

    var summary: String {
        "共 \(total) 条 · 收藏 \(favorites) 条 · \(characters) 字符"
    }
}
