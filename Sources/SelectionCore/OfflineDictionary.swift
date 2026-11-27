import Foundation

/// 随 App 打包的离线英汉词库（ECDICT 精简版，约 5.6 万词条）。
/// 只用于单个单词/连字符词的快速释义，不替代整句翻译。
final class OfflineDictionary {
    static let shared = OfflineDictionary()

    private var entries: [String: String] = [:]
    private(set) var isLoaded = false

    private init() {}

    /// 选中的内容是否适合先查词库：单个 token，长度不超过 40。
    static func isLookupCandidate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        guard trimmed.split(whereSeparator: { $0.isWhitespace }).count == 1 else { return false }
        return trimmed.rangeOfCharacter(from: .letters) != nil
    }

    /// 查词；找不到返回 nil。首次调用时才加载词库。
    func lookup(_ text: String) -> String? {
        loadIfNeeded()

        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        guard !key.isEmpty else { return nil }

        if let definition = entries[key], !definition.isEmpty {
            return definition
        }

        // 简单处理所有格和常见屈折变化；只在原词查不到时尝试。
        var candidates: [String] = []
        if key.hasSuffix("'s"), key.count > 3 {
            candidates.append(String(key.dropLast(2)))
        }
        for suffix in ["es", "ed", "ing", "s"] where key.hasSuffix(suffix) && key.count > suffix.count + 2 {
            candidates.append(String(key.dropLast(suffix.count)))
        }
        for candidate in candidates {
            if let definition = entries[candidate], !definition.isEmpty {
                return definition
            }
        }
        return nil
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "ecdict", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        entries.reserveCapacity(60_000)
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let word = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !word.isEmpty, word != "word" else { continue }
            let definition = String(parts[1])
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !definition.isEmpty else { continue }
            entries[word] = definition
        }
    }
}
