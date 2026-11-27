import Foundation

struct ProviderPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let baseURL: String
    let model: String
    let note: String
    let requiresKey: Bool

    static let all: [ProviderPreset] = [
        .init(
            id: "deepseek",
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            note: "在线，速度快，需要 API Key",
            requiresKey: true
        ),
        .init(
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            note: "在线，通用，需要 API Key",
            requiresKey: true
        ),
        .init(
            id: "ollama",
            name: "Ollama",
            baseURL: "http://127.0.0.1:11434/v1",
            model: "qwen2.5:3b",
            note: "本地，无需 Key，需要先启动 Ollama",
            requiresKey: false
        ),
        .init(
            id: "lmstudio",
            name: "LM Studio",
            baseURL: "http://127.0.0.1:1234/v1",
            model: "local-model",
            note: "本地，无需 Key，需要先启动 LM Studio",
            requiresKey: false
        )
    ]
}

struct ProviderHealthResult: Sendable {
    let ok: Bool
    let message: String
}

enum ProviderHealth {
    static func check(baseURL: String, apiKey: String, model: String) async -> ProviderHealthResult {
        let base = normalizedBase(baseURL)
        guard let modelsURL = URL(string: base + "/models") else {
            return ProviderHealthResult(ok: false, message: "Base URL 格式无效")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ProviderHealthResult(ok: false, message: "没有收到 HTTP 响应")
            }

            if (200..<300).contains(http.statusCode) {
                let modelCount = decodeModelCount(data)
                let suffix = modelCount > 0 ? "，发现 \(modelCount) 个模型" : ""
                return ProviderHealthResult(ok: true, message: "连接正常\(suffix)。当前模型：\(model)")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return ProviderHealthResult(ok: false, message: "API Key 无效或没有权限（HTTP \(http.statusCode)）")
            }
            if http.statusCode == 404, isLocal(base) {
                return await checkOllamaTags(base: base)
            }
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            return ProviderHealthResult(
                ok: false,
                message: "HTTP \(http.statusCode)\(body.isEmpty ? "" : "：\(body)")"
            )
        } catch {
            return ProviderHealthResult(ok: false, message: "连接失败：\(error.localizedDescription)")
        }
    }

    private static func checkOllamaTags(base: String) async -> ProviderHealthResult {
        let root = base.replacingOccurrences(of: "/v1", with: "")
        guard let url = URL(string: root + "/api/tags") else {
            return ProviderHealthResult(ok: false, message: "Ollama 地址无效")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return ProviderHealthResult(ok: false, message: "Ollama 没有响应")
            }
            let count = decodeModelCount(data)
            return ProviderHealthResult(ok: true, message: "本地 Ollama 连接正常，发现 \(count) 个模型。")
        } catch {
            return ProviderHealthResult(ok: false, message: "本地 Ollama 未启动：\(error.localizedDescription)")
        }
    }

    private static func normalizedBase(_ raw: String) -> String {
        EndpointURL.normalizedBase(raw)
    }

    private static func isLocal(_ base: String) -> Bool {
        EndpointURL.isLocal(base)
    }

    private static func decodeModelCount(_ data: Data) -> Int {
        struct Response: Decodable {
            struct Model: Decodable { let id: String?; let name: String? }
            let data: [Model]?
            let models: [Model]?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return 0 }
        return decoded.data?.count ?? decoded.models?.count ?? 0
    }
}
