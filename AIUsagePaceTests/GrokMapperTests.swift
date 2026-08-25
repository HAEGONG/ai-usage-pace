import XCTest
@testable import AIUsagePace

final class GrokMapperTests: XCTestCase {
    func testWeeklyFixtureMapsSingleMeter() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let snapshot = try GrokUsageMapper.snapshot(
            from: try decodeFixture(),
            session: .accountGrok,
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.providerID, "grok")
        XCTAssertEqual(snapshot.accountFingerprint, GrokSession.accountGrok.accountFingerprint)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.membershipType, "unified")
        XCTAssertEqual(snapshot.limitType, "USAGE_PERIOD_TYPE_WEEKLY")
        XCTAssertNil(snapshot.totalPercentUsed)
        XCTAssertEqual(snapshot.cycleStart, isoDate("2026-06-01T00:00:00Z"))
        XCTAssertEqual(snapshot.cycleEnd, isoDate("2026-06-08T00:00:00Z"))
        XCTAssertEqual(snapshot.buckets.map(\.id), [.grokWeekly])
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 42.5)
        XCTAssertNil(absoluteUsage(snapshot.buckets[0]))
    }

    func testUnknownFieldsAreIgnoredByDecoder() throws {
        let json = Data(#"""
        {
          "config": {
            "creditUsagePercent": 1,
            "productUsage": [{ "product": "GrokBuild", "usagePercent": 1 }],
            "prepaidBalance": { "val": 0 }
          },
          "unexpectedField": true
        }
        """#.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(GrokBillingResponse.self, from: json))
    }

    func testOmittedPercentWithWeeklyPeriodIsZero() throws {
        let response = GrokBillingResponse(
            config: GrokBillingConfig(
                creditUsagePercent: nil,
                currentPeriod: GrokUsagePeriod(
                    type: GrokUsageMapper.weeklyPeriodType,
                    start: "2026-06-01T00:00:00Z",
                    end: "2026-06-08T00:00:00Z"
                ),
                billingPeriodStart: nil,
                billingPeriodEnd: nil,
                isUnifiedBillingUser: true
            )
        )
        let snapshot = try GrokUsageMapper.snapshot(
            from: response,
            session: .accountGrok,
            capturedAt: Date()
        )
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 0)
    }

    func testMissingConfigIsUsageUnavailable() {
        XCTAssertThrowsError(
            try GrokUsageMapper.snapshot(from: GrokBillingResponse(config: nil), session: .accountGrok, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testMissingPercentAndPeriodIsUsageUnavailable() {
        let response = GrokBillingResponse(config: GrokBillingConfig(
            creditUsagePercent: nil,
            currentPeriod: nil,
            billingPeriodStart: nil,
            billingPeriodEnd: nil,
            isUnifiedBillingUser: nil
        ))
        XCTAssertThrowsError(
            try GrokUsageMapper.snapshot(from: response, session: .accountGrok, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testMonthlyPeriodIsUnsupportedAccountType() {
        let response = GrokBillingResponse(
            config: GrokBillingConfig(
                creditUsagePercent: 10,
                currentPeriod: GrokUsagePeriod(type: "USAGE_PERIOD_TYPE_MONTHLY", start: nil, end: nil),
                billingPeriodStart: nil,
                billingPeriodEnd: nil,
                isUnifiedBillingUser: nil
            )
        )
        XCTAssertThrowsError(
            try GrokUsageMapper.snapshot(from: response, session: .accountGrok, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testUnparseableCycleDateIsUnsupportedResponseSchema() throws {
        var response = try decodeFixture()
        var config = try XCTUnwrap(response.config)
        var period = try XCTUnwrap(config.currentPeriod)
        period.start = "not-a-date"
        config.currentPeriod = period
        response.config = config
        XCTAssertThrowsError(
            try GrokUsageMapper.snapshot(from: response, session: .accountGrok, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedResponseSchema)
        }
    }

    func testFractionalOffsetTimestampIsParsed() throws {
        let response = GrokBillingResponse(
            config: GrokBillingConfig(
                creditUsagePercent: 12,
                currentPeriod: GrokUsagePeriod(
                    type: GrokUsageMapper.weeklyPeriodType,
                    start: "2026-07-07T10:46:52.885620+00:00",
                    end: "2026-07-14T10:46:52.885620+00:00"
                ),
                billingPeriodStart: nil,
                billingPeriodEnd: nil,
                isUnifiedBillingUser: nil
            )
        )
        let snapshot = try GrokUsageMapper.snapshot(
            from: response,
            session: .accountGrok,
            capturedAt: Date()
        )
        XCTAssertNotNil(snapshot.cycleStart)
        XCTAssertNotNil(snapshot.cycleEnd)
    }

    func testPercentOverOneHundredIsPreserved() throws {
        let response = GrokBillingResponse(
            config: GrokBillingConfig(
                creditUsagePercent: 150,
                currentPeriod: GrokUsagePeriod(type: GrokUsageMapper.weeklyPeriodType, start: nil, end: nil),
                billingPeriodStart: nil,
                billingPeriodEnd: nil,
                isUnifiedBillingUser: nil
            )
        )
        let snapshot = try GrokUsageMapper.snapshot(
            from: response,
            session: .accountGrok,
            capturedAt: Date()
        )
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 150)
    }

    private func decodeFixture() throws -> GrokBillingResponse {
        let url = try XCTUnwrap(
            Bundle(for: GrokMapperTests.self).url(forResource: "billing-credits-weekly", withExtension: "json")
        )
        return try JSONDecoder().decode(GrokBillingResponse.self, from: Data(contentsOf: url))
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

    private func isoDate(_ raw: String) -> Date {
        ISO8601Timestamp.date(from: raw)!
    }
}

extension GrokSession {
    static let accountGrok = GrokSession(
        accessToken: "token-g",
        subject: "grok-user-1",
        accountFingerprint: "ggg"
    )
}
