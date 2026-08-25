import XCTest
@testable import AIUsagePace

final class CursorUsageProviderTests: XCTestCase {
    func testGrokBotUsesTheSameCursorFingerprint() async throws {
        let loader = CountingSessionLoader(session: .accountA)
        let provider = makeProvider(loader: loader, grokBotStatus: 200, grokBotBody: subscribedGrokBotBody())
        let snapshot = try await fetchUsage(from: provider)

        XCTAssertEqual(snapshot.accountFingerprint, CursorSession.accountA.accountFingerprint)
        XCTAssertEqual(snapshot.buckets.map(\.id), [.cursorModels, .otherModels, .grokBotWeekly])
        XCTAssertEqual(snapshot.buckets[2].cycleStart, ISO8601Timestamp.date(from: "2026-08-20T00:00:00Z"))
        XCTAssertNil(snapshot.buckets[2].cycleEnd)
        XCTAssertTrue(snapshot.poolErrors.isEmpty)
    }

    func testFetchUsageReadsTheCursorSessionOnce() async throws {
        let loader = CountingSessionLoader(session: .accountA)
        let provider = makeProvider(loader: loader, grokBotStatus: 200, grokBotBody: subscribedGrokBotBody())
        _ = try await fetchUsage(from: provider)
        XCTAssertEqual(loader.count, 1)
    }

    func testGrokBotFailureKeepsCursorModelsAndOtherModels() async throws {
        let provider = makeProvider(
            loader: CountingSessionLoader(session: .accountA),
            grokBotStatus: 401,
            grokBotBody: Data()
        )
        let snapshot = try await fetchUsage(from: provider)

        XCTAssertEqual(snapshot.buckets.map(\.id), [.cursorModels, .otherModels])
        XCTAssertEqual(snapshot.poolErrors[.grokBotWeekly], .authenticationExpired)
        XCTAssertEqual(snapshot.accountFingerprint, CursorSession.accountA.accountFingerprint)
    }

    func testGrokBotNetworkFailureDoesNotThrow() async throws {
        let provider = makeProvider(
            loader: CountingSessionLoader(session: .accountA),
            grokBotStatus: 503,
            grokBotBody: Data()
        )
        let snapshot = try await fetchUsage(from: provider)
        XCTAssertEqual(snapshot.buckets.map(\.id), [.cursorModels, .otherModels])
        XCTAssertEqual(snapshot.poolErrors[.grokBotWeekly], .networkFailure)
    }

    func testIneligibleGrokBotOmitsBucketWithoutPoolError() async throws {
        let body = Data(#"""
        {"usagePercent":0,"hasNonZeroIncludedLimit":false}
        """#.utf8)
        let provider = makeProvider(
            loader: CountingSessionLoader(session: .accountA),
            grokBotStatus: 200,
            grokBotBody: body
        )
        let snapshot = try await fetchUsage(from: provider)
        XCTAssertEqual(snapshot.buckets.map(\.id), [.cursorModels, .otherModels])
        XCTAssertTrue(snapshot.poolErrors.isEmpty)
    }

    func testEligibleGrokBotWithoutPercentIsPoolErrorNotZero() async throws {
        let body = Data(#"""
        {"hasNonZeroIncludedLimit":true}
        """#.utf8)
        let provider = makeProvider(
            loader: CountingSessionLoader(session: .accountA),
            grokBotStatus: 200,
            grokBotBody: body
        )
        let snapshot = try await fetchUsage(from: provider)
        XCTAssertEqual(snapshot.buckets.map(\.id), [.cursorModels, .otherModels])
        XCTAssertEqual(snapshot.poolErrors[.grokBotWeekly], .usageUnavailable)
    }

    func testCursorModelsCycleStaysMonthlyWhenGrokBotIsWeekly() async throws {
        let provider = makeProvider(
            loader: CountingSessionLoader(session: .accountA),
            grokBotStatus: 200,
            grokBotBody: resetGrokBotBody()
        )
        let snapshot = try await fetchUsage(from: provider)
        let cursor = try XCTUnwrap(snapshot.buckets.first { $0.id == .cursorModels })
        let grokBot = try XCTUnwrap(snapshot.buckets.first { $0.id == .grokBotWeekly })
        XCTAssertEqual(cursor.cycleStart, snapshot.cycleStart)
        XCTAssertEqual(cursor.cycleEnd, snapshot.cycleEnd)
        XCTAssertNotEqual(grokBot.cycleStart, cursor.cycleStart)
        XCTAssertNotEqual(grokBot.cycleEnd, cursor.cycleEnd)
    }

    private func makeProvider(
        loader: CountingSessionLoader,
        grokBotStatus: Int,
        grokBotBody: Data
    ) -> CursorUsageProvider {
        let http = RoutingHTTPClient(
            responses: [
                CursorAPIClient.usageSummaryURL.path: (200, usageSummaryBody()),
                GrokBotAPIClient.sandUsageStatusURL.path: (grokBotStatus, grokBotBody),
            ]
        )
        return CursorUsageProvider(
            sessionLoader: loader,
            apiClient: CursorAPIClient(http: http),
            grokBotClient: GrokBotAPIClient(http: http)
        )
    }

    private func fetchUsage(from provider: CursorUsageProvider) async throws -> UsageSnapshot {
        let session = try await provider.loadSession()
        return try await session.fetchUsage()
    }

    private func usageSummaryBody() -> Data {
        let url = Bundle(for: CursorUsageProviderTests.self).url(
            forResource: "usage-summary-pro-plus",
            withExtension: "json"
        )!
        return try! Data(contentsOf: url)
    }

    private func subscribedGrokBotBody() -> Data {
        let url = Bundle(for: CursorUsageProviderTests.self).url(
            forResource: "sand-usage-status-subscribed",
            withExtension: "json"
        )!
        return try! Data(contentsOf: url)
    }

    private func resetGrokBotBody() -> Data {
        let url = Bundle(for: CursorUsageProviderTests.self).url(
            forResource: "sand-usage-status-with-reset",
            withExtension: "json"
        )!
        return try! Data(contentsOf: url)
    }
}

private final class CountingSessionLoader: SessionLoading, @unchecked Sendable {
    var count = 0
    var session: CursorSession

    init(session: CursorSession) {
        self.session = session
    }

    func loadSession() async throws -> CursorSession {
        count += 1
        return session
    }
}

private final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    var responses: [String: (Int, Data)]

    init(responses: [String: (Int, Data)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let (status, body) = responses[path] ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://cursor.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
