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
        let notes: [[String: Any]] = records.map { record in
            var back = record.translatedText
            if !record.context.isEmpty {
                back += "\n\n---\n语境：\n" + String(record.context.prefix(1200))
            }
            return [
                "deckName": deck.isEmpty ? "Default" : deck,
                "modelName": model.isEmpty ? "Basic" : model,
                "fields": [
                    "Front": record.sourceText,
                    "Back": back
                ],
                "tags": tagList,
                "options": ["allowDuplicate": false]
            ]
        }
        let result = try await request(
            urlString: urlString,
            action: "addNotes",
            params: ["notes": notes]
        )
        guard let ids = result as? [Any] else {
            throw AnkiConnectError.requestFailed("addNotes 返回格式不正确。")
        }
        return ids.filter { !($0 is NSNull) }.count
    }

    private static func request(
        urlString: String,
        action: String,
        params: [String: Any]
    ) async throws -> Any {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            throw AnkiConnectError.invalidURL
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
