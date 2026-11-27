import Foundation

/// A small, process-local guard for the public URL scheme.
///
/// The scheme is deliberately unauthenticated so browser extensions and
/// Shortcuts can call it without a shared secret. This gate limits accidental
/// or malicious bursts and rejects oversized payloads before a model request.
struct ExternalURLGate {
    static let maxTextCharacters = 20_000
    static let maxRequestsPerMinute = 60

    private var acceptedAt: [Date] = []

    mutating func accept(textLength: Int, now: Date = Date()) -> Bool {
        guard textLength > 0, textLength <= Self.maxTextCharacters else { return false }
        acceptedAt.removeAll { now.timeIntervalSince($0) >= 60 }
        guard acceptedAt.count < Self.maxRequestsPerMinute else { return false }
        acceptedAt.append(now)
        return true
    }
}
