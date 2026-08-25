import Foundation

enum GrokUsageMapper {
    static let providerID = "grok"
    static let weeklyPeriodType = "USAGE_PERIOD_TYPE_WEEKLY"

    static func snapshot(
        from response: GrokBillingResponse,
        session: GrokSession,
        capturedAt: Date
    ) throws -> UsageSnapshot {
        guard let config = response.config else {
            throw AppError.usageUnavailable
        }

        try rejectUnsupportedPeriod(config.currentPeriod?.type)

        let percentUsed: Double
        switch (config.creditUsagePercent, config.currentPeriod) {
        case let (percent?, _):
            percentUsed = percent
        case (nil, .some):
            percentUsed = 0
        case (nil, nil):
            throw AppError.usageUnavailable
        }

        return UsageSnapshot(
            providerID: providerID,
            accountFingerprint: session.accountFingerprint,
            capturedAt: capturedAt,
            cycleStart: try parseCycleDate(config.currentPeriod?.start ?? config.billingPeriodStart),
            cycleEnd: try parseCycleDate(config.currentPeriod?.end ?? config.billingPeriodEnd),
            buckets: [
                UsageBucket(
                    id: .grokWeekly,
                    meter: .metered(percentUsed: percentUsed, absolute: nil)
                ),
            ],
            membershipType: config.isUnifiedBillingUser == true ? "unified" : nil,
            limitType: config.currentPeriod?.type,
            totalPercentUsed: nil
        )
    }

    private static func rejectUnsupportedPeriod(_ type: String?) throws {
        guard let type, !type.isEmpty else { return }
        if type != weeklyPeriodType {
            throw AppError.unsupportedAccountType
        }
    }

    private static func parseCycleDate(_ raw: String?) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = ISO8601Timestamp.date(from: raw) {
            return date
        }
        throw AppError.unsupportedResponseSchema
    }
}
