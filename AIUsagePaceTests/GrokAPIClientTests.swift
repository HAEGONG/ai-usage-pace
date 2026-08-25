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

private struct GrokStubHTTPClient: HTTPClient {
    var statusCode: Int
    var body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? GrokAPIClient.billingURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
