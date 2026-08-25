import XCTest
@testable import AIUsagePace

final class CodexAuthReaderTests: XCTestCase {
    func testTokensObjectYieldsAccessTokenAndAccountID() throws {
        let token = syntheticJWT(sub: "codex-user-1", exp: 10_000)
        let json = """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "\(token)",
            "access_token": "\(token)",
            "refresh_token": "should-not-be-required",
            "account_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
          },
          "last_refresh": "2026-08-25T08:02:00.000Z"
        }
        """
        let credentials = try CodexAuthReader.credentials(from: Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, token)
        XCTAssertEqual(credentials.accountID, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertFalse(credentials.accessToken.contains("should-not-be-required"))
    }

    func testAPIKeyOnlyLoginIsCodexLoginNotFound() {
        let json = #"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-not-a-plan-subscription"}"#
        XCTAssertThrowsError(try CodexAuthReader.credentials(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? AppError, .codexLoginNotFound)
        }
    }

    func testEmptyAccessTokenIsCodexLoginNotFound() {
        let json = #"{"tokens":{"access_token":""}}"#
        XCTAssertThrowsError(try CodexAuthReader.credentials(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? AppError, .codexLoginNotFound)
        }
    }

    func testMalformedJSONIsUnableToReadCodexSession() {
        XCTAssertThrowsError(try CodexAuthReader.credentials(from: Data("{".utf8))) { error in
            XCTAssertEqual(error as? AppError, .unableToReadCodexSession)
        }
    }

    func testMissingFileIsCodexLoginNotFound() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-codex-\(UUID().uuidString).json")
        let reader = CodexAuthReader(filePath: missing)
        do {
            _ = try await reader.loadSession()
            XCTFail("Expected codexLoginNotFound")
        } catch {
            XCTAssertEqual(error as? AppError, .codexLoginNotFound)
        }
    }

    func testExpiredTokenThrowsWithoutNeedingNetwork() {
        let token = syntheticJWT(sub: "codex-user-1", exp: 1_000)
        let now = Date(timeIntervalSince1970: 1_000 - 30)
        XCTAssertThrowsError(
            try CodexAuthReader.session(fromAccessToken: token, accountID: nil, now: now)
        ) { error in
            XCTAssertEqual(error as? AppError, .sessionExpired)
        }
    }

    func testValidTokenProducesFingerprintWithoutToken() throws {
        let token = syntheticJWT(sub: "codex-user-1", exp: 10_000)
        let session = try CodexAuthReader.session(
            fromAccessToken: token,
            accountID: "account-1",
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(session.subject, "codex-user-1")
        XCTAssertEqual(session.accountID, "account-1")
        XCTAssertEqual(session.accountFingerprint.count, 64)
        XCTAssertFalse(session.accountFingerprint.contains(token))
        XCTAssertEqual(session.accountFingerprint, JWTAccessToken.fingerprint(for: "codex-user-1"))
    }

    func testAccountIDFallsBackToAccessTokenClaim() throws {
        let token = jwtWithAuthClaim(sub: "codex-user-1", exp: 10_000, accountID: "claimed-account")
        let session = try CodexAuthReader.session(
            fromAccessToken: token,
            accountID: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(session.accountID, "claimed-account")
    }

    func testStoredAccountIDWinsOverAccessTokenClaim() throws {
        let token = jwtWithAuthClaim(sub: "codex-user-1", exp: 10_000, accountID: "claimed-account")
        let session = try CodexAuthReader.session(
            fromAccessToken: token,
            accountID: "stored-account",
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(session.accountID, "stored-account")
    }

    func testMissingAccountIDLeavesSessionUnscoped() throws {
        let token = syntheticJWT(sub: "codex-user-1", exp: 10_000)
        let session = try CodexAuthReader.session(
            fromAccessToken: token,
            accountID: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertNil(session.accountID)
    }

    func testMalformedAccessTokenIsUnableToReadCodexSession() {
        XCTAssertThrowsError(
            try CodexAuthReader.session(
                fromAccessToken: "not-a-jwt",
                accountID: nil,
                now: Date(timeIntervalSince1970: 1_000)
            )
        ) { error in
            XCTAssertEqual(error as? AppError, .unableToReadCodexSession)
        }
    }

    func testLoadSessionReadsTempFile() async throws {
        let token = syntheticJWT(sub: "codex-user-1", exp: 10_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-\(UUID().uuidString).json")
        let json = """
        {"auth_mode":"chatgpt","tokens":{"access_token":"\(token)","account_id":"account-1"}}
        """
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = CodexAuthReader(
            filePath: url,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let session = try await reader.loadSession()
        XCTAssertEqual(session.accessToken, token)
        XCTAssertEqual(session.accountID, "account-1")
        XCTAssertEqual(session.subject, "codex-user-1")
    }

    private func jwtWithAuthClaim(sub: String, exp: Int, accountID: String) -> String {
        let header = base64URLEncoded(["alg": "none", "typ": "JWT"])
        let payload = base64URLEncoded([
            "sub": sub,
            "exp": exp,
            "https://api.openai.com/auth": ["chatgpt_account_id": accountID],
        ])
        return "\(header).\(payload).sig"
    }

    private func base64URLEncoded(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
