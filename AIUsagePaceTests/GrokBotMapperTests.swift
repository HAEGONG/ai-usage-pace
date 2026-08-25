import XCTest
@testable import AIUsagePace

final class GrokBotMapperTests: XCTestCase {
    func testSubscribedFixtureMapsWeeklyPercentWithoutInferredReset() throws {
        let bucket = try XCTUnwrap(GrokBotUsageMapper.bucket(from: try decodeFixture("sand-usage-status-subscribed")))

        XCTAssertEqual(bucket.id, .grokBotWeekly)
        XCTAssertEqual(percentUsed(bucket), 0)
        XCTAssertEqual(bucket.cycleStart, isoDate("2026-08-20T00:00:00Z"))
        XCTAssertNil(bucket.cycleEnd)
        XCTAssertNil(absoluteUsage(bucket))
    }

    func testExplicitResetIsUsedWhenPresent() throws {
        let response = GrokBotUsageStatusResponse(
            currentPeriodStart: "2026-08-20T00:00:00Z",
            nextResetTimestampUtc: "2026-08-30T00:00:00Z",
            usagePercent: 1,
            hasNonZeroIncludedLimit: true
        )
        let bucket = try XCTUnwrap(GrokBotUsageMapper.bucket(from: response))
        XCTAssertEqual(bucket.cycleStart, isoDate("2026-08-20T00:00:00Z"))
        XCTAssertEqual(bucket.cycleEnd, isoDate("2026-08-30T00:00:00Z"))
    }

    func testResetFixtureMapsWeeklyStartAndEnd() throws {
        let bucket = try XCTUnwrap(GrokBotUsageMapper.bucket(from: try decodeFixture("sand-usage-status-with-reset")))

        XCTAssertEqual(percentUsed(bucket), 37.5)
        XCTAssertEqual(bucket.cycleStart, isoDate("2026-08-17T07:57:50.647Z"))
        XCTAssertEqual(bucket.cycleEnd, isoDate("2026-08-24T07:57:50.647Z"))
    }

    func testUnknownFieldsAreIgnoredByDecoder() throws {
        let json = Data(#"""
        {
          "usagePercent": 12,
          "hasNonZeroIncludedLimit": true,
          "unexpectedField": { "nested": true }
        }
        """#.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(GrokBotUsageStatusResponse.self, from: json))
    }

    func testMissingIncludedLimitOmitsBucket() throws {
        let response = GrokBotUsageStatusResponse(
            currentPeriodStart: "2026-08-20T00:00:00Z",
            usagePercent: 0,
            hasNonZeroIncludedLimit: false
        )
        XCTAssertNil(try GrokBotUsageMapper.bucket(from: response))
    }

    func testNilIncludedLimitOmitsBucketRatherThanDefaultingPercent() throws {
        let response = GrokBotUsageStatusResponse(usagePercent: 40)
        XCTAssertNil(try GrokBotUsageMapper.bucket(from: response))
    }

    func testIncludedLimitZeroOmitsBucket() throws {
        let response = GrokBotUsageStatusResponse(
            usagePercent: 10,
            hasNonZeroIncludedLimit: true,
            includedLimitZero: true
        )
        XCTAssertNil(try GrokBotUsageMapper.bucket(from: response))
    }

    func testPooledEnterpriseAllowanceOmitsBucket() throws {
        let response = GrokBotUsageStatusResponse(
            usagePercent: 10,
            hasNonZeroIncludedLimit: true,
            usesPooledEnterpriseAllowance: true
        )
        XCTAssertNil(try GrokBotUsageMapper.bucket(from: response))
    }

    func testEligibleResponseWithoutPercentIsUsageUnavailable() {
        let response = GrokBotUsageStatusResponse(hasNonZeroIncludedLimit: true)
        XCTAssertThrowsError(try GrokBotUsageMapper.bucket(from: response)) { error in
            XCTAssertEqual(error as? AppError, .usageUnavailable)
        }
    }

    func testUnparseableCycleDateIsUnsupportedResponseSchema() {
        let response = GrokBotUsageStatusResponse(
            currentPeriodStart: "not-a-date",
            usagePercent: 10,
            hasNonZeroIncludedLimit: true
        )
        XCTAssertThrowsError(try GrokBotUsageMapper.bucket(from: response)) { error in
            XCTAssertEqual(error as? AppError, .unsupportedResponseSchema)
        }
    }

    func testUnparseableResetDateIsUnsupportedResponseSchema() {
        let response = GrokBotUsageStatusResponse(
            nextResetTimestampUtc: "not-a-date",
            usagePercent: 10,
            hasNonZeroIncludedLimit: true
        )
        XCTAssertThrowsError(try GrokBotUsageMapper.bucket(from: response)) { error in
            XCTAssertEqual(error as? AppError, .unsupportedResponseSchema)
        }
    }

    func testPercentOverOneHundredIsPreserved() throws {
        let response = GrokBotUsageStatusResponse(
            usagePercent: 150,
            hasNonZeroIncludedLimit: true
        )
        let bucket = try XCTUnwrap(GrokBotUsageMapper.bucket(from: response))
        XCTAssertEqual(percentUsed(bucket), 150)
    }

    func testZeroPercentIsMappedNotTreatedAsMissing() throws {
        let response = GrokBotUsageStatusResponse(
            usagePercent: 0,
            hasNonZeroIncludedLimit: true
        )
        let bucket = try XCTUnwrap(GrokBotUsageMapper.bucket(from: response))
        XCTAssertEqual(percentUsed(bucket), 0)
        XCTAssertNil(bucket.cycleStart)
        XCTAssertNil(bucket.cycleEnd)
    }

    private func decodeFixture(_ name: String) throws -> GrokBotUsageStatusResponse {
        let url = try XCTUnwrap(
            Bundle(for: GrokBotMapperTests.self).url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder().decode(GrokBotUsageStatusResponse.self, from: Data(contentsOf: url))
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
