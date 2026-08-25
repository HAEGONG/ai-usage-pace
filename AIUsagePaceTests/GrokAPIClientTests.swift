import XCTest
@testable import AIUsagePace

final class GrokAPIClientTests: XCTestCase {
    func test401And403AreAuthenticationExpired() async {
        await assertStatus(401, throws: .authenticationExpired)
        await assertStatus(403, throws: .authenticationExpired)
    }

    func test204IsUsageUnavailable() async {
        await assertStatus(204, throws: .usageUnavailable)
    }

    func testInvalidJSONIsUnsupportedResponseSchema() async {
        let client = GrokAPIClient(http: GrokStubHTTPClient(statusCode: 200, body: Data("{".utf8)))
        await assertAppError(
            { try await client.fetchSnapshot(session: .accountGrok, now: Date()) },
            .unsupportedResponseSchema
        )
    }

    func test200FixtureMapsWeeklyPool() async throws {
        let url = try XCTUnwrap(
            Bundle(for: GrokAPIClientTests.self).url(forResource: "billing-credits-weekly", withExtension: "json")
        )
        let client = GrokAPIClient(http: GrokStubHTTPClient(statusCode: 200, body: try Data(contentsOf: url)))
        let snapshot = try await client.fetchSnapshot(session: .accountGrok, now: Date())
        XCTAssertEqual(snapshot.buckets.map(\.id), [.grokWeekly])
        XCTAssertEqual(snapshot.providerID, "grok")
    }

    func testRequestUsesCreditsEndpointAndAuthHeaders() async throws {
        let stub = GrokStubHTTPClient(statusCode: 204, body: Data())
        let client = GrokAPIClient(http: stub)

        // 204 maps to usageUnavailable; we only care that the request was built
        // correctly before the response was handled.
        _ = try? await client.fetchSnapshot(session: .accountGrok, now: Date())

        let request = try XCTUnwrap(stub.capturedRequest)
        XCTAssertEqual(request.url, GrokAPIClient.billingURL)
        XCTAssertEqual(request.url?.absoluteString, "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(GrokSession.accountGrok.accessToken)"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    private func assertStatus(_ status: Int, throws expected: AppError) async {
        let client = GrokAPIClient(http: GrokStubHTTPClient(statusCode: status, body: Data()))
        await assertAppError(
            { try await client.fetchSnapshot(session: .accountGrok, now: Date()) },
            expected
        )
    }

    private func assertAppError(
        _ work: @escaping () async throws -> UsageSnapshot,
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

private final class GrokStubHTTPClient: HTTPClient, @unchecked Sendable {
    let statusCode: Int
    let body: Data
    private(set) var capturedRequest: URLRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? GrokAPIClient.billingURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
