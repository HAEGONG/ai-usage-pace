import Foundation

struct GrokBotUsageStatusResponse: Decodable, Sendable {
    var currentPeriodStart: String? = nil
    var nextResetTimestampUtc: String? = nil
    var usagePercent: Double? = nil
    var hasAvailableUsage: Bool? = nil
    var hasNonZeroIncludedLimit: Bool? = nil
    var includedLimitZero: Bool? = nil
    var usesPooledEnterpriseAllowance: Bool? = nil
}
