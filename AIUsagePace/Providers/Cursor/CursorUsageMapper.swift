import Foundation

enum CursorUsageMapper {
    static let providerID = "cursor"

    static let unsupportedMembershipTypes: Set<String> = [
        "team",
        "enterprise",
        "business",
    ]

    static func snapshot(
        from response: CursorUsageSummaryResponse,
        session: CursorSession,
        capturedAt: Date
    ) throws -> UsageSnapshot {
        try rejectUnsupportedAccount(response)

        let plan = response.individualUsage?.plan
        switch (plan?.autoPercentUsed, plan?.apiPercentUsed) {
        case let (autoPercentUsed?, apiPercentUsed?):
            return UsageSnapshot(
                providerID: providerID,
                accountFingerprint: session.accountFingerprint,
                capturedAt: capturedAt,
                cycleStart: try parseCycleDate(response.billingCycleStart),
                cycleEnd: try parseCycleDate(response.billingCycleEnd),
                buckets: [
                    UsageBucket(
                        id: .cursorModels,
                        meter: .metered(percentUsed: autoPercentUsed, absolute: nil)
                    ),
                    UsageBucket(
                        id: .otherModels,
                        meter: .metered(percentUsed: apiPercentUsed, absolute: nil)
                    ),
                ],
                membershipType: response.membershipType,
                limitType: response.limitType,
                totalPercentUsed: plan?.totalPercentUsed
            )
        case (nil, nil):
            if response.teamUsage?.pooled != nil {
                throw AppError.unsupportedAccountType
            }
            throw AppError.usageUnavailable
        default:
            throw AppError.unsupportedResponseSchema
        }
    }

    private static func rejectUnsupportedAccount(_ response: CursorUsageSummaryResponse) throws {
        if response.isUnlimited == true {
            throw AppError.unsupportedAccountType
        }

        let membership = response.membershipType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let membership, unsupportedMembershipTypes.contains(membership) {
            throw AppError.unsupportedAccountType
        }
        if response.limitType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "team" {
            throw AppError.unsupportedAccountType
        }
    }

    private static func parseCycleDate(_ raw: String?) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = iso8601Date(from: raw) {
            return date
        }
        throw AppError.unsupportedResponseSchema
    }

    private static func iso8601Date(from raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) {
            return date
        }

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: raw)
    }
}
