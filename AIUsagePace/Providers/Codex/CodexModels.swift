import Foundation

struct CodexUsageResponse: Decodable, Sendable {
    var planType: String?
    var rateLimit: CodexRateLimit?
}

struct CodexRateLimit: Decodable, Sendable {
    var primaryWindow: CodexRateLimitWindow?
    var secondaryWindow: CodexRateLimitWindow?
}

struct CodexRateLimitWindow: Decodable, Sendable {
    var usedPercent: Double?
    var limitWindowSeconds: Double?
    var resetAfterSeconds: Double?
    var resetAt: Double?
}

enum CodexUsageDecoding {
    /// The ChatGPT backend serialises usage in snake_case, unlike the Cursor and
    /// Grok endpoints.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
