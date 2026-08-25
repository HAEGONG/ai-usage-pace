import XCTest
@testable import AIUsagePace

final class CursorMapperTests: XCTestCase {
    func testProPlusFixtureMapsTwoIndependentMeters() throws {
        let response = try decodeFixture()
        let capturedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let snapshot = try CursorUsageMapper.snapshot(
            from: response,
            session: .accountA,
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.providerID, "cursor")
        XCTAssertEqual(snapshot.accountFingerprint, CursorSession.accountA.accountFingerprint)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.membershipType, "pro_plus")
        XCTAssertEqual(snapshot.limitType, "user")
        XCTAssertEqual(snapshot.totalPercentUsed, 0.5075697211155379)
        XCTAssertEqual(snapshot.cycleStart, isoDate("2026-08-24T07:17:13.000Z"))
        XCTAssertEqual(snapshot.cycleEnd, isoDate("2026-09-24T07:17:13.000Z"))
        XCTAssertEqual(snapshot.buckets.map(\.id), [.cursorModels, .otherModels])
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 0.5308333333333334)
        XCTAssertEqual(percentUsed(snapshot.buckets[1]), 0)
        XCTAssertEqual(snapshot.buckets[0].cycleStart, snapshot.cycleStart)
        XCTAssertEqual(snapshot.buckets[0].cycleEnd, snapshot.cycleEnd)
        XCTAssertEqual(snapshot.buckets[1].cycleStart, snapshot.cycleStart)
        XCTAssertEqual(snapshot.buckets[1].cycleEnd, snapshot.cycleEnd)
        XCTAssertNil(absoluteUsage(snapshot.buckets[0]))
        XCTAssertNil(absoluteUsage(snapshot.buckets[1]))
    }

    func testPlanUsedIsNotTreatedAsTotalQuota() throws {
        let snapshot = try CursorUsageMapper.snapshot(
            from: try decodeFixture(),
            session: .accountA,
            capturedAt: Date()
        )

        let usedOverLimitPercent = 637.0 / 7000.0 * 100.0
        XCTAssertEqual(snapshot.buckets.count, 2)
        for bucket in snapshot.buckets {
            XCTAssertNotEqual(percentUsed(bucket), usedOverLimitPercent)
            XCTAssertNil(absoluteUsage(bucket))
        }
        XCTAssertNotEqual(snapshot.totalPercentUsed, usedOverLimitPercent)
    }

    func testUnknownFieldsAreIgnoredByDecoder() throws {
        let json = Data(#"""
        {
          "membershipType": "pro",
          "isUnlimited": false,
          "unexpectedField": { "nested": true }
        }
        """#.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: json))
    }

    func testTeamMembershipIsUnsupportedAccountType() throws {
        let response = CursorUsageSummaryResponse(membershipType: "team")
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testBusinessMembershipIsUnsupportedAccountType() throws {
        let response = CursorUsageSummaryResponse(membershipType: "business")
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testEnterpriseMembershipIsUnsupportedAccountType() throws {
        let response = CursorUsageSummaryResponse(membershipType: "enterprise")
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testTeamLimitTypeIsUnsupportedAccountType() throws {
        let response = CursorUsageSummaryResponse(membershipType: "pro_plus", limitType: "team")
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testUnlimitedIsUnsupportedUntilFixtureExists() {
        let response = CursorUsageSummaryResponse(isUnlimited: true)
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testPooledTeamUsageOnlyIsUnsupportedAccountType() {
        let response = CursorUsageSummaryResponse(
            teamUsage: CursorTeamUsage(pooled: CursorOverallUsage(used: 10, limit: 100))
        )
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedAccountType)
        }
    }

    func testMissingRequiredUsageIsUsageUnavailableNotUnsupportedAccount() {
        let response = CursorUsageSummaryResponse(membershipType: "pro")
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testSinglePoolPercentIsUnsupportedResponseSchema() {
        let response = CursorUsageSummaryResponse(
            membershipType: "pro_plus",
            individualUsage: CursorIndividualUsage(
                plan: CursorPlanUsage(autoPercentUsed: 12)
            )
        )
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedResponseSchema)
        }
    }

    func testUnparseableCycleDateIsUnsupportedResponseSchema() throws {
        var response = try decodeFixture()
        response.billingCycleStart = "not-a-date"
        XCTAssertThrowsError(
            try CursorUsageMapper.snapshot(from: response, session: .accountA, capturedAt: Date())
        ) { error in
            XCTAssertEqual(error as? AppError, .unsupportedResponseSchema)
        }
    }

    func testPercentOverOneHundredIsPreserved() throws {
        let response = CursorUsageSummaryResponse(
            membershipType: "pro_plus",
            individualUsage: CursorIndividualUsage(
                plan: CursorPlanUsage(autoPercentUsed: 150, apiPercentUsed: 0)
            )
        )
        let snapshot = try CursorUsageMapper.snapshot(
            from: response,
            session: .accountA,
            capturedAt: Date()
        )
        XCTAssertEqual(percentUsed(snapshot.buckets[0]), 150)
    }

    private func decodeFixture() throws -> CursorUsageSummaryResponse {
        let url = try XCTUnwrap(
            Bundle(for: CursorMapperTests.self).url(forResource: "usage-summary-pro-plus", withExtension: "json")
        )
        return try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: Data(contentsOf: url))
    }
}

private extension CursorMapperTests {
    func percentUsed(_ bucket: UsageBucket) -> Double {
        switch bucket.meter {
        case .metered(let percentUsed, _):
            return percentUsed
        }
    }

    func absoluteUsage(_ bucket: UsageBucket) -> AbsoluteUsage? {
        switch bucket.meter {
        case .metered(_, let absolute):
            return absolute
        }
    }

    func isoDate(_ raw: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)!
    }
}

private extension CursorUsageSummaryResponse {
    init(
        membershipType: String? = nil,
        limitType: String? = nil,
        isUnlimited: Bool? = nil,
        individualUsage: CursorIndividualUsage? = nil,
        teamUsage: CursorTeamUsage? = nil
    ) {
        self.init(
            billingCycleStart: nil,
            billingCycleEnd: nil,
            membershipType: membershipType,
            limitType: limitType,
            isUnlimited: isUnlimited,
            individualUsage: individualUsage,
            teamUsage: teamUsage
        )
    }
}

private extension CursorIndividualUsage {
    init(plan: CursorPlanUsage?) {
        self.init(plan: plan, onDemand: nil, overall: nil)
    }
}

private extension CursorPlanUsage {
    init(autoPercentUsed: Double? = nil, apiPercentUsed: Double? = nil) {
        self.init(
            enabled: true,
            used: nil,
            limit: nil,
            remaining: nil,
            autoPercentUsed: autoPercentUsed,
            apiPercentUsed: apiPercentUsed,
            totalPercentUsed: nil
        )
    }
}

private extension CursorTeamUsage {
    init(pooled: CursorOverallUsage?) {
        self.init(onDemand: nil, pooled: pooled)
    }
}

private extension CursorOverallUsage {
    init(used: Int?, limit: Int?) {
        self.init(enabled: nil, used: used, limit: limit, remaining: nil)
    }
}
