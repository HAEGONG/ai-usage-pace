import XCTest
@testable import AIUsagePace

final class HTTPClientAllowlistTests: XCTestCase {
    func testRejectsNonHTTPSAndUnknownHosts() {
        XCTAssertThrowsError(try AllowlistedHTTPClient.validate(url: URL(string: "http://cursor.com/api/usage-summary")))
        XCTAssertThrowsError(try AllowlistedHTTPClient.validate(url: URL(string: "https://example.com")))
        XCTAssertNoThrow(try AllowlistedHTTPClient.validate(url: URL(string: "https://cursor.com/api/usage-summary")))
        XCTAssertNoThrow(try AllowlistedHTTPClient.validate(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")))
    }

    func testRedirectAllowlistRejectsUnknownHosts() {
        let allowed = AllowlistedHTTPClient.allowedHosts
        XCTAssertNotNil(
            RedirectHostGuard.acceptedRedirect(
                from: URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!),
                allowedHosts: allowed
            )
        )
        XCTAssertNil(
            RedirectHostGuard.acceptedRedirect(
                from: URLRequest(url: URL(string: "https://evil.example/steal")!),
                allowedHosts: allowed
            )
        )
        XCTAssertNotNil(
            RedirectHostGuard.acceptedRedirect(
                from: URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!),
                allowedHosts: allowed
            )
        )
        XCTAssertNil(
            RedirectHostGuard.acceptedRedirect(
                from: URLRequest(url: URL(string: "http://cursor.com/api/usage-summary")!),
                allowedHosts: allowed
            )
        )
    }
}

final class AppErrorTests: XCTestCase {
    func testErrorCasesAreDistinct() {
        XCTAssertNotEqual(AppError.unsupportedAccountType, AppError.unsupportedResponseSchema)
        XCTAssertNotEqual(AppError.unsupportedAccountType, AppError.usageUnavailable)
        XCTAssertEqual(AppError.unsupportedAccountType.localizedDescription, "Unsupported account type")
        XCTAssertEqual(AppError.unsupportedResponseSchema.localizedDescription, "Usage response changed")
        XCTAssertEqual(AppError.grokLoginNotFound.localizedDescription, "Grok login not found")
        XCTAssertNotEqual(
            AppError.unsupportedResponseSchema.localizedDescription,
            AppError.networkFailure.localizedDescription
        )
    }
}
