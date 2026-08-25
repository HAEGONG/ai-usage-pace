import XCTest
@testable import AIUsagePace

final class GrokAuthReaderTests: XCTestCase {
    func testKeyedAuthFileReadsKeyAndIgnoresRefreshToken() throws {
        let token = syntheticJWT(sub: "grok-user-1", exp: 10_000)
        let json = """
        {
          "https://auth.x.ai::00000000-0000-0000-0000-000000000001": {
            "key": "\(token)",
            "refresh_token": "should-not-be-required",
            "email": "hidden@example.com"
          }
        }
        """
        let parsed = try GrokAuthReader.accessToken(from: Data(json.utf8))
        XCTAssertEqual(parsed, token)
        XCTAssertFalse(parsed.contains("should-not-be-required"))
    }

    func testSimpleAccessTokenFormIsAccepted() throws {
        let token = syntheticJWT(sub: "grok-user-1", exp: 10_000)
        let json = """
        {"access_token":"\(token)","expires_in":3600,"issuer":"https://auth.x.ai"}
        """
        XCTAssertEqual(try GrokAuthReader.accessToken(from: Data(json.utf8)), token)
    }

    func testMissingFileIsGrokLoginNotFound() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-grok-\(UUID().uuidString).json")
        let reader = GrokAuthReader(filePath: missing)
        do {
            _ = try await reader.loadSession()
            XCTFail("Expected grokLoginNotFound")
        } catch {
            XCTAssertEqual(error as? AppError, .grokLoginNotFound)
        }
    }

    func testEmptyKeyedFileIsGrokLoginNotFound() throws {
        XCTAssertThrowsError(try GrokAuthReader.accessToken(from: Data("{}".utf8))) { error in
            XCTAssertEqual(error as? AppError, .grokLoginNotFound)
        }
    }

    func testExpiredTokenThrowsWithoutNeedingNetwork() {
        let token = syntheticJWT(sub: "grok-user-1", exp: 1_000)
        let now = Date(timeIntervalSince1970: 1_000 - 30)
        XCTAssertThrowsError(try GrokAuthReader.session(fromAccessToken: token, now: now)) { error in
            XCTAssertEqual(error as? AppError, .sessionExpired)
        }
    }

    func testValidTokenProducesFingerprintWithoutToken() throws {
        let token = syntheticJWT(sub: "grok-user-1", exp: 10_000)
        let session = try GrokAuthReader.session(
            fromAccessToken: token,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(session.subject, "grok-user-1")
        XCTAssertEqual(session.accountFingerprint.count, 64)
        XCTAssertFalse(session.accountFingerprint.contains(token))
        XCTAssertEqual(session.accountFingerprint, JWTAccessToken.fingerprint(for: "grok-user-1"))
    }

    func testPrefersUnexpiredKeyedSession() throws {
        let expired = syntheticJWT(sub: "old", exp: 1_000)
        let valid = syntheticJWT(sub: "new", exp: 4_000_000_000)
        let json = """
        {
          "https://auth.x.ai::old": { "key": "\(expired)" },
          "https://auth.x.ai::new": { "key": "\(valid)" }
        }
        """
        XCTAssertEqual(try GrokAuthReader.accessToken(from: Data(json.utf8)), valid)
    }

    func testMalformedJSONIsUnableToReadGrokSession() {
        XCTAssertThrowsError(try GrokAuthReader.accessToken(from: Data("{".utf8))) { error in
            XCTAssertEqual(error as? AppError, .unableToReadGrokSession)
        }
    }

    func testLoadSessionReadsTempFile() async throws {
        let token = syntheticJWT(sub: "grok-user-1", exp: 10_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-auth-\(UUID().uuidString).json")
        let json = """
        {"https://auth.x.ai::client":{"key":"\(token)"}}
        """
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = GrokAuthReader(
            filePath: url,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let session = try await reader.loadSession()
        XCTAssertEqual(session.accessToken, token)
        XCTAssertEqual(session.subject, "grok-user-1")
    }
}
