import XCTest
@testable import AIUsagePace

final class CodexMapperTests: XCTestCase {
    func testWeeklyPrimaryWindowFixtureMapsWeeklyPool() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_787_645_898)
        let snapshot = try CodexUsageMapper.snapshot(
            from: try decodeFixture(),
            session: .accountCodex,
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.providerID, "codex")
        XCTAssertEqual(snapshot.accountFingerprint, CodexSession.accountCodex.accountFingerprint)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.membershipType, "plus")
        XCTAssertNil(snapshot.limitType)
        XCTAssertNil(snapshot.totalPercentUsed)
        XCTAssertNil(snapshot.cycleStart)
        XCTAssertNil(snapshot.cycleEnd)

        // A Plus account reports its 7-day allowance in the primary slot, so the
        // pool must come from the window length rather than the slot.
        XCTAssertEqual(snapshot.buckets.map(\.id), [.codexWeekly])
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 35)
        XCTAssertNil(absoluteUsage(snapshot.buckets[0]))
        XCTAssertEqual(snapshot.buckets[0].cycleEnd, Date(timeIntervalSince1970: 1_788_133_126))
        XCTAssertEqual(
            snapshot.buckets[0].cycleStart,
            Date(timeIntervalSince1970: 1_788_133_126 - 604_800)
        )
    }

    func testShortWindowMapsSessionPool() throws {
        let snapshot = try snapshot(
            primary: CodexRateLimitWindow(
                usedPercent: 12,
                limitWindowSeconds: 18_000,
                resetAfterSeconds: nil,
                resetAt: 2_000_000_000
            )
        )
        XCTAssertEqual(snapshot.buckets.map(\.id), [.codexSession])
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 12)
        XCTAssertEqual(
            snapshot.buckets[0].cycleStart,
            Date(timeIntervalSince1970: 2_000_000_000 - 18_000)
        )
    }

    func testBothWindowsMapToSessionAndWeekly() throws {
        let snapshot = try snapshot(
            primary: CodexRateLimitWindow(
                usedPercent: 40,
                limitWindowSeconds: 18_000,
                resetAfterSeconds: nil,
                resetAt: 2_000_000_000
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 55,
                limitWindowSeconds: 604_800,
                resetAfterSeconds: nil,
                resetAt: 2_000_500_000
            )
        )
        XCTAssertEqual(snapshot.buckets.map(\.id), [.codexSession, .codexWeekly])
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 40)
        XCTAssertEqual(percentUsed(snapshot.buckets[1]), 55)
    }

    func testTwoWindowsOfTheSameLengthKeepThePrimaryOnly() throws {
        let window = CodexRateLimitWindow(
            usedPercent: 21,
            limitWindowSeconds: 604_800,
            resetAfterSeconds: nil,
            resetAt: 2_000_000_000
        )
        var secondary = window
        secondary.usedPercent = 99
        let snapshot = try snapshot(primary: window, secondary: secondary)

        XCTAssertEqual(snapshot.buckets.map(\.id), [.codexWeekly])
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 21)
    }

    func testWindowWithoutLengthIsTreatedAsWeekly() throws {
        let snapshot = try snapshot(
            primary: CodexRateLimitWindow(
                usedPercent: 5,
                limitWindowSeconds: nil,
                resetAfterSeconds: nil,
                resetAt: 2_000_000_000
            )
        )
        XCTAssertEqual(snapshot.buckets.map(\.id), [.codexWeekly])
        XCTAssertNil(snapshot.buckets[0].cycleStart)
        XCTAssertEqual(snapshot.buckets[0].cycleEnd, Date(timeIntervalSince1970: 2_000_000_000))
    }

    func testResetAfterSecondsIsUsedWhenResetAtIsMissing() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_000_000)
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(
                    usedPercent: 8,
                    limitWindowSeconds: 604_800,
                    resetAfterSeconds: 3_600,
                    resetAt: nil
                ),
                secondaryWindow: nil
            )
        )
        let snapshot = try CodexUsageMapper.snapshot(
            from: response,
            session: .accountCodex,
            capturedAt: capturedAt
        )
        XCTAssertEqual(snapshot.buckets[0].cycleEnd, capturedAt.addingTimeInterval(3_600))
    }

    func testPercentOverOneHundredIsPreserved() throws {
        let snapshot = try snapshot(
            primary: CodexRateLimitWindow(
                usedPercent: 140,
                limitWindowSeconds: 604_800,
                resetAfterSeconds: nil,
                resetAt: 2_000_000_000
            )
        )
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 140)
    }

    func testMissingRateLimitIsUsageUnavailable() {
        let response = CodexUsageResponse(planType: "plus", rateLimit: nil)
        XCTAssertThrowsError(
            try CodexUsageMapper.snapshot(from: response, session: .accountCodex, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testWindowsWithoutPercentAreUsageUnavailable() {
        let response = CodexUsageResponse(
            planType: "plus",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(
                    usedPercent: nil,
                    limitWindowSeconds: 604_800,
                    resetAfterSeconds: nil,
                    resetAt: 2_000_000_000
                ),
                secondaryWindow: nil
            )
        )
        XCTAssertThrowsError(
            try CodexUsageMapper.snapshot(from: response, session: .accountCodex, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testBothWindowsNullIsUsageUnavailable() {
        let response = CodexUsageResponse(
            planType: "plus",
            rateLimit: CodexRateLimit(primaryWindow: nil, secondaryWindow: nil)
        )
        XCTAssertThrowsError(
            try CodexUsageMapper.snapshot(from: response, session: .accountCodex, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testUnknownFieldsAreIgnoredByDecoder() throws {
        let json = Data(#"""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": { "used_percent": 3, "limit_window_seconds": 604800 },
            "secondary_window": null,
            "brand_new_field": { "nested": true }
          },
          "unexpected_top_level": [1, 2, 3]
        }
        """#.utf8)
        let response = try CodexUsageDecoding.makeDecoder().decode(CodexUsageResponse.self, from: json)
        XCTAssertEqual(response.planType, "plus")
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 3)
    }

    private func snapshot(
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow? = nil
    ) throws -> UsageSnapshot {
        try CodexUsageMapper.snapshot(
            from: CodexUsageResponse(
                planType: "plus",
                rateLimit: CodexRateLimit(primaryWindow: primary, secondaryWindow: secondary)
            ),
            session: .accountCodex,
            capturedAt: Date(timeIntervalSince1970: 1_787_645_898)
        )
    }

    private func decodeFixture() throws -> CodexUsageResponse {
        let url = try XCTUnwrap(
            Bundle(for: CodexMapperTests.self).url(forResource: "wham-usage-plus-weekly", withExtension: "json")
        )
        return try CodexUsageDecoding.makeDecoder().decode(
            CodexUsageResponse.self,
            from: Data(contentsOf: url)
        )
    }

    private func percentUsed(_ bucket: UsageBucket) -> Double {
        switch bucket.meter {
        case .metered(let percentUsed, _):
            return percentUsed
        }
    }

    private func absoluteUsage(_ bucket: UsageBucket) -> AbsoluteUsage? {
        switch bucket.meter {
        case .metered(_, let absolute):
            return absolute
        }
    }
}

extension CodexSession {
    static let accountCodex = CodexSession(
        accessToken: "token-c",
        accountID: "account-c",
        subject: "codex-user-1",
        accountFingerprint: "ccc"
    )
}
