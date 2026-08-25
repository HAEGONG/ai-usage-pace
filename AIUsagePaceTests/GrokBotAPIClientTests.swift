import XCTest
@testable import AIUsagePace

final class GrokBotAPIClientTests: XCTestCase {
    func test401And403AreAuthenticationExpired() async {
        await assertStatus(401, throws: .authenticationExpired)
        await assertStatus(403, throws: .authenticationExpired)
    }

    func test204IsUsageUnavailable() async {
        await assertStatus(204, throws: .usageUnavailable)
    }

    func testInvalidJSONIsUnsupportedResponseSchema() async {
        let client = GrokBotAPIClient(http: GrokBotStubHTTPClient(statusCode: 200, body: Data("{".utf8)))
        await assertAppError(
            { try await client.fetchStatus(session: .accountA) },
            .unsupportedResponseSchema
        )
    }

    func test200FixtureDecodesUsagePercent() async throws {
        let url = try XCTUnwrap(
            Bundle(for: GrokBotAPIClientTests.self).url(
                forResource: "sand-usage-status-subscribed",
                withExtension: "json"
            )
        )
        let client = GrokBotAPIClient(http: GrokBotStubHTTPClient(statusCode: 200, body: try Data(contentsOf: url)))
        let status = try await client.fetchStatus(session: .accountA)
        XCTAssertEqual(status.usagePercent, 0)
        XCTAssertEqual(status.hasNonZeroIncludedLimit, true)
        XCTAssertEqual(status.currentPeriodStart, "2026-08-20T00:00:00Z")
        XCTAssertNil(status.nextResetTimestampUtc)
    }

    func testRequestUsesPostOriginCookieAndSandEndpoint() async throws {
        let http = GrokBotStubHTTPClient(
            statusCode: 200,
            body: Data(#"{"hasNonZeroIncludedLimit":true,"usagePercent":1}"#.utf8)
        )
        let client = GrokBotAPIClient(http: http)
        _ = try await client.fetchStatus(session: .accountA)

        let request = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GrokBotAPIClient.sandUsageStatusURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
        let cookie = try XCTUnwrap(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertTrue(cookie.hasPrefix("WorkosCursorSessionToken="))
        XCTAssertTrue(cookie.contains("user_a%3A%3A"))
        XCTAssertFalse(cookie.contains("::"))
    }

    private func assertStatus(_ status: Int, throws expected: AppError) async {
        let client = GrokBotAPIClient(http: GrokBotStubHTTPClient(statusCode: status, body: Data()))
        await assertAppError(
            { try await client.fetchStatus(session: .accountA) },
            expected
        )
    }

    private func assertAppError(
        _ work: @escaping () async throws -> GrokBotUsageStatusResponse,
        _ expected: AppError
    ) async {
        do {
            _ = try await work()
            XCTFail("expected \(expected)")
        } catch let error as AppError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

private final class GrokBotStubHTTPClient: HTTPClient, @unchecked Sendable {
    var statusCode: Int
    var body: Data
    var lastRequest: URLRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? GrokBotAPIClient.sandUsageStatusURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
