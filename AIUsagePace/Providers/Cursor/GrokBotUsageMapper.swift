import Foundation

enum GrokBotUsageMapper {
    static func bucket(from response: GrokBotUsageStatusResponse) throws -> UsageBucket? {
        if response.usesPooledEnterpriseAllowance == true {
            return nil
        }
        if response.includedLimitZero == true {
            return nil
        }
        guard response.hasNonZeroIncludedLimit == true else {
            return nil
        }
        guard let percentUsed = response.usagePercent else {
            throw AppError.usageUnavailable
        }

        let cycleStart = try parseCycleDate(response.currentPeriodStart)
        let cycleEnd = try parseCycleDate(response.nextResetTimestampUtc)

        return UsageBucket(
            id: .grokBotWeekly,
            meter: .metered(percentUsed: percentUsed, absolute: nil),
            cycleStart: cycleStart,
            cycleEnd: cycleEnd
        )
    }

    private static func parseCycleDate(_ raw: String?) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = ISO8601Timestamp.date(from: raw) {
            return date
        }
        throw AppError.unsupportedResponseSchema
    }
}
