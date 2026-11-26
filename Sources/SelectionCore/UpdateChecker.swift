import Foundation

struct UpdateRelease: Codable, Equatable, Sendable {
    let version: String
    let build: Int?
    let url: String
    let notes: String?

    init(version: String, build: Int? = nil, url: String, notes: String? = nil) {
        self.version = version
        self.build = build
        self.url = url
        self.notes = notes
    }
}

enum UpdateCheckerError: LocalizedError {
    case noFeed
    case invalidFeedURL
    case invalidFeed
    case noDownloadURL

    var errorDescription: String? {
        switch self {
        case .noFeed:
            return "还没有配置更新源。请在设置 → 数据与权限里填入更新 JSON 地址。"
        case .invalidFeedURL:
            return "更新源地址无效。"
        case .invalidFeed:
            return "更新源返回内容不是有效的版本 JSON。"
        case .noDownloadURL:
            return "更新源没有提供下载地址。"
        }
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case available(UpdateRelease)
    case upToDate(UpdateRelease?)
    case notConfigured
}

enum UpdateChecker {
    /// Feed shape:
    /// {"version":"0.4.0","build":4,"url":"https://example.com/app.zip","notes":"..."}
    static func parse(_ data: Data) throws -> UpdateRelease {
        guard let release = try? JSONDecoder().decode(UpdateRelease.self, from: data) else {
            throw UpdateCheckerError.invalidFeed
        }
        guard !release.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UpdateCheckerError.invalidFeed
        }
        return release
    }

    static func check(
        feedURL: String,
        currentVersion: String,
        currentBuild: Int,
        session: URLSession = .shared
    ) async throws -> UpdateCheckResult {
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notConfigured }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw UpdateCheckerError.invalidFeedURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateCheckerError.invalidFeed
        }
        let release = try parse(data)
        guard URL(string: release.url) != nil else {
            throw UpdateCheckerError.noDownloadURL
        }

        if isNewer(release, than: currentVersion, build: currentBuild) {
            return .available(release)
        }
        return .upToDate(release)
    }

    static func isNewer(_ release: UpdateRelease, than currentVersion: String, build currentBuild: Int) -> Bool {
        let newParts = numericParts(release.version)
        let oldParts = numericParts(currentVersion)
        let count = max(newParts.count, oldParts.count)
        for index in 0..<count {
            let new = index < newParts.count ? newParts[index] : 0
            let old = index < oldParts.count ? oldParts[index] : 0
            if new != old {
                return new > old
            }
        }
        guard let newBuild = release.build else { return false }
        return newBuild > currentBuild
    }

    static func numericParts(_ version: String) -> [Int] {
        version
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .prefix(4)
            .compactMap { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits)
            }
    }
}
