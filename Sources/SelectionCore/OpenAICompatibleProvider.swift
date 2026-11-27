import Foundation

enum ProviderError: LocalizedError {
    case invalidURL
    case insecureTransport
    case missingAPIKey
    case http(Int, String)
    case stream(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API 地址无效"
        case .insecureTransport:
            return "公网 API 地址必须使用 HTTPS，避免 API Key 和译文在明文连接中泄露"
        case .missingAPIKey:
            return "还没有 API Key"
        case .http(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "HTTP \(code)\(trimmed.isEmpty ? "" : ": \(trimmed.prefix(300))")"
        case .stream(let message):
            return "模型返回错误：\(message.prefix(300))"
        case .emptyResponse:
            return "模型没有返回内容"
        }
    }
}

struct OpenAICompatibleProvider: Sendable {
    func stream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        _ request: TranslationRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var base = EndpointURL.normalizedBase(request.apiBaseURL)
        if !base.hasSuffix("/chat/completions") {
            base += "/chat/completions"
        }
        guard let url = URL(string: base),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw ProviderError.invalidURL
        }
        guard EndpointURL.isPermittedTransport(base) else {
            throw ProviderError.insecureTransport
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        if !request.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let safeTemperature = min(max(request.temperature, 0), 2)
        let safeMaxTokens = min(max(request.maxOutputTokens, 1), 8_192)
        let body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "temperature": safeTemperature,
            "max_tokens": safeMaxTokens,
            "messages": PromptBuilder.translationMessages(for: request)
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 {
                    break
                }
            }
            throw ProviderError.http(http.statusCode, errorBody)
        }

        var didReceiveContent = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }
            guard let data = payload.data(using: .utf8) else { continue }
            // Some OpenAI-compatible servers report mid-stream failures as a
            // data frame with an error object instead of closing the stream.
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProviderError.stream(message)
            }
            guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let content = chunk.choices.first?.delta.content,
                  !content.isEmpty else {
                continue
            }
            didReceiveContent = true
            continuation.yield(content)
        }

        if !didReceiveContent {
            throw ProviderError.emptyResponse
        }
    }
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}
