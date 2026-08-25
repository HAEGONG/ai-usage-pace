import XCTest
@testable import AIUsagePace

final class CodexAPIClientTests: XCTestCase {
    func test401And403AreAuthenticationExpired() async {
        await assertStatus(401, throws: .authenticationExpired)
        await assertStatus(403, throws: .authenticationExpired)
    }

    func test204IsUsageUnavailable() async {
        await assertStatus(204, throws: .usageUnavailable)
    }

    func test500IsNetworkFailure() async {
        await assertStatus(500, throws: .networkFailure)
    }

    func testInvalidJSONIsUnsupportedResponseSchema() async {
        let client = CodexAPIClient(http: CodexStubHTTPClient(statusCode: 200, body: Data("{".utf8)))
        await assertAppError(
            { try await client.fetchSnapshot(session: .accountCodex, now: Date()) },
            .unsupportedResponseSchema
        )
    }

    func test200FixtureMapsWeeklyPool() async throws {
        let url = try XCTUnwrap(
            Bundle(for: CodexAPIClientTests.self).url(forResource: "wham-usage-plus-weekly", withExtension: "json")
        )
        let client = CodexAPIClient(http: CodexStubHTTPClient(statusCode: 200, body: try Data(contentsOf: url)))
        let snapshot = try await client.fetchSnapshot(session: .accountCodex, now: Date())
        XCTAssertEqual(snapshot.buckets.map(\.id), [.codexWeekly])
        XCTAssertEqual(snapshot.providerID, "codex")
        XCTAssertEqual(snapshot.membershipType, "plus")
    }

    func testRequestUsesUsageEndpointAndAuthHeaders() async throws {
        let stub = CodexStubHTTPClient(statusCode: 204, body: Data())
        let client = CodexAPIClient(http: stub)

        // 204 maps to usageUnavailable; we only care that the request was built
        // correctly before the response was handled.
        _ = try? await client.fetchSnapshot(session: .accountCodex, now: Date())

        let request = try XCTUnwrap(stub.capturedRequest)
        XCTAssertEqual(request.url, CodexAPIClient.usageURL)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(CodexSession.accountCodex.accessToken)"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "ChatGPT-Account-Id"),
            CodexSession.accountCodex.accountID
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testRequestOmitsAccountHeaderWhenSessionHasNoAccountID() async throws {
        let stub = CodexStubHTTPClient(statusCode: 204, body: Data())
        let client = CodexAPIClient(http: stub)
        let session = CodexSession(
            accessToken: "token-c",
            accountID: nil,
            subject: "codex-user-1",
            accountFingerprint: "ccc"
        )

        _ = try? await client.fetchSnapshot(session: session, now: Date())

        let request = try XCTUnwrap(stub.capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }

    func testUsageEndpointIsAllowlisted() throws {
        XCTAssertNoThrow(try AllowlistedHTTPClient.validate(url: CodexAPIClient.usageURL))
    }

    private func assertStatus(_ status: Int, throws expected: AppError) async {
        let client = CodexAPIClient(http: CodexStubHTTPClient(statusCode: status, body: Data()))
        await assertAppError(
            { try await client.fetchSnapshot(session: .accountCodex, now: Date()) },
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

private final class CodexStubHTTPClient: HTTPClient, @unchecked Sendable {
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
            url: request.url ?? CodexAPIClient.usageURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
