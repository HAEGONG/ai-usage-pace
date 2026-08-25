import XCTest
@testable import AIUsagePace

final class FixturePrivacyTests: XCTestCase {
    func testFixturesDoNotContainTokensCookiesEmailsOrUserIDs() throws {
        let urls = try XCTUnwrap(Bundle(for: FixturePrivacyTests.self).urls(forResourcesWithExtension: "json", subdirectory: nil))
        XCTAssertFalse(urls.isEmpty)

        let email = try NSRegularExpression(pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])
        let jwt = try NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_\-]+=*\.[A-Za-z0-9_\-]+=*\.[A-Za-z0-9_\-]+=*"#)
        let forbidden = [
            "WorkosCursorSessionToken",
            "refresh_token",
            "refreshToken",
            "access_token",
            "Bearer ",
            "user_01",
        ]

        for url in urls {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertEqual(email.numberOfMatches(in: text, range: range), 0, url.lastPathComponent)
            XCTAssertEqual(jwt.numberOfMatches(in: text, range: range), 0, url.lastPathComponent)
            for needle in forbidden {
                XCTAssertFalse(text.contains(needle), "\(url.lastPathComponent) contains \(needle)")
            }
        }
    }
}
