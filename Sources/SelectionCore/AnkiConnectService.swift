import Foundation

enum AnkiConnectError: LocalizedError {
    case invalidURL
    case unreachable(String)
    case requestFailed(String)
    case ankiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "AnkiConnect 地址无效。"
        case .unreachable(let message): return "连接 AnkiConnect 失败：\(message)"
        case .requestFailed(let message): return "AnkiConnect 请求失败：\(message)"
        case .ankiError(let message): return "AnkiConnect 返回错误：\(message)"
        }
    }
}

enum AnkiConnectService {
    private static let version = 6

    static func test(urlString: String) async throws -> String {
        let decks = try await deckNames(urlString: urlString)
        return "已连接，牌组 \(decks.count) 个。"
    }

    static func deckNames(urlString: String) async throws -> [String] {
        let result = try await request(
            urlString: urlString,
            action: "deckNames",
            params: [:]
        )
        guard let decks = result as? [String] else {
            throw AnkiConnectError.requestFailed("deckNames 返回格式不正确。")
        }
        return decks
    }

    static func addNotes(
        records: [QueryRecord],
        urlString: String,
        deck: String,
        model: String,
        tags: String
    ) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        let tagList = tags
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }

        // Do not put thousands of notes into one JSON request. A large export
        // can exceed AnkiConnect's request timeout or the URLSession body
        // budget; bounded batches keep progress and retries manageable.
        let batchSize = 100
        var added = 0
        for start in stride(from: 0, to: records.count, by: batchSize) {
            let end = min(start + batchSize, records.count)
            let notes: [[String: Any]] = records[start..<end].map { record in
                note(for: record, deck: deck, model: model, tags: tagList)
            }
            let result = try await request(
                urlString: urlString,
                action: "addNotes",
                params: ["notes": notes]
            )
            guard let ids = result as? [Any] else {
                throw AnkiConnectError.requestFailed("addNotes 返回格式不正确。")
            }
            added += ids.filter { !($0 is NSNull) }.count
        }
        return added
    }

    static func note(
        for record: QueryRecord,
        deck: String,
        model: String,
        tags: [String]
    ) -> [String: Any] {
        var back = record.translatedText
        if !record.context.isEmpty {
            back += "\n\n---\n语境：\n" + String(record.context.prefix(1200))
        }
        return [
            "deckName": deck.isEmpty ? "Default" : deck,
            "modelName": model.isEmpty ? "Basic" : model,
            "fields": [
                // Anki fields are HTML. Escape page-controlled text so a
                // selection containing markup is shown literally and cannot
                // load remote resources inside a review card.
                "Front": ankiHTML(record.sourceText),
                "Back": ankiHTML(back)
            ],
            "tags": tags,
            "options": ["allowDuplicate": false]
        ]
    }

    private static func ankiHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func request(
        urlString: String,
        action: String,
        params: [String: Any]
    ) async throws -> Any {
        let normalized = EndpointURL.normalized(urlString)
        guard !normalized.isEmpty,
              let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw AnkiConnectError.invalidURL
        }
        guard EndpointURL.isPermittedTransport(normalized) else {
            throw AnkiConnectError.requestFailed("公网 AnkiConnect 地址必须使用 HTTPS")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": action,
            "version": version,
            "params": params
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AnkiConnectError.requestFailed("没有 HTTP 响应。")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AnkiConnectError.requestFailed("HTTP \(http.statusCode)")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AnkiConnectError.requestFailed("返回不是 JSON 对象。")
            }
            if let error = object["error"] as? String, !error.isEmpty {
                throw AnkiConnectError.ankiError(error)
            }
            guard let result = object["result"] else {
                throw AnkiConnectError.requestFailed("缺少 result 字段。")
            }
            return result
        } catch let error as AnkiConnectError {
            throw error
        } catch {
            throw AnkiConnectError.unreachable(error.localizedDescription)
        }
    }
}
