import XCTest
@testable import AIUsagePace

final class HTTPClientAllowlistTests: XCTestCase {
    func testRejectsNonHTTPSAndUnknownHosts() {
        XCTAssertThrowsError(try AllowlistedHTTPClient.validate(url: URL(string: "http://cursor.com/api/usage-summary")))
        XCTAssertThrowsError(try AllowlistedHTTPClient.validate(url: URL(string: "https://example.com")))
        XCTAssertNoThrow(try AllowlistedHTTPClient.validate(url: URL(string: "https://cursor.com/api/usage-summary")))
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
        XCTAssertEqual(AppError.unsupportedResponseSchema.localizedDescription, "Cursor usage response changed")
        XCTAssertNotEqual(
            AppError.unsupportedResponseSchema.localizedDescription,
            AppError.networkFailure.localizedDescription
        )
    }
}
