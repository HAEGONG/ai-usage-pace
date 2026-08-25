import Foundation

enum CodexUsageMapper {
    static let providerID = "codex"

    /// Windows shorter than a day are the rolling "session" allowance; anything
    /// longer is the subscription's weekly allowance.
    static let sessionWindowCeiling: TimeInterval = 24 * 60 * 60

    static func snapshot(
        from response: CodexUsageResponse,
        session: CodexSession,
        capturedAt: Date
    ) throws -> UsageSnapshot {
        guard let rateLimit = response.rateLimit else {
            throw AppError.usageUnavailable
        }

        var buckets: [UsageBucket] = []
        // The API reports two slots rather than two named windows, and which
        // window lands in which slot varies by plan: a Plus account can report
        // its 7-day allowance as `primary_window` with no secondary at all. The
        // pool is therefore derived from the window length, not the slot.
        for window in [rateLimit.primaryWindow, rateLimit.secondaryWindow] {
            guard let window, let bucket = bucket(from: window, capturedAt: capturedAt) else {
                continue
            }
            guard !buckets.contains(where: { $0.id == bucket.id }) else { continue }
            buckets.append(bucket)
        }

        guard !buckets.isEmpty else {
            throw AppError.usageUnavailable
        }

        return UsageSnapshot(
            providerID: providerID,
            accountFingerprint: session.accountFingerprint,
            capturedAt: capturedAt,
            cycleStart: nil,
            cycleEnd: nil,
            buckets: buckets,
            membershipType: response.planType,
            limitType: nil,
            totalPercentUsed: nil
        )
    }

    private static func bucket(
        from window: CodexRateLimitWindow,
        capturedAt: Date
    ) -> UsageBucket? {
        guard let usedPercent = window.usedPercent else { return nil }

        let cycleEnd = cycleEnd(of: window, capturedAt: capturedAt)
        let cycleStart = window.limitWindowSeconds.flatMap { seconds in
            cycleEnd?.addingTimeInterval(-seconds)
        }

        return UsageBucket(
            id: pool(for: window.limitWindowSeconds),
            meter: .metered(percentUsed: usedPercent, absolute: nil),
            cycleStart: cycleStart,
            cycleEnd: cycleEnd
        )
    }

    private static func cycleEnd(of window: CodexRateLimitWindow, capturedAt: Date) -> Date? {
        if let resetAt = window.resetAt, resetAt > 0 {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let resetAfterSeconds = window.resetAfterSeconds {
            return capturedAt.addingTimeInterval(resetAfterSeconds)
        }
        return nil
    }

    private static func pool(for limitWindowSeconds: Double?) -> UsagePoolID {
        guard let limitWindowSeconds, limitWindowSeconds < sessionWindowCeiling else {
            return .codexWeekly
        }
        return .codexSession
    }
}
