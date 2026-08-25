import Foundation

struct CodexSession: Equatable, Sendable {
    let accessToken: String
    let accountID: String?
    let subject: String
    let accountFingerprint: String
}

struct CodexAuthReader: Sendable {
    var filePath: URL
    var now: @Sendable () -> Date

    init(
        filePath: URL = CodexAuthReader.defaultFilePath,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.filePath = filePath
        self.now = now
    }

    static var defaultFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    func loadSession() async throws -> CodexSession {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw AppError.codexLoginNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: filePath)
        } catch {
            throw AppError.unableToReadCodexSession
        }

        let credentials = try Self.credentials(from: data)
        return try Self.session(
            fromAccessToken: credentials.accessToken,
            accountID: credentials.accountID,
            now: now()
        )
    }

    static func session(
        fromAccessToken accessToken: String,
        accountID: String?,
        now: Date
    ) throws -> CodexSession {
        let payload: [String: Any]
        do {
            payload = try JWTAccessToken.payload(accessToken)
        } catch {
            throw AppError.unableToReadCodexSession
        }

        let subject: String
        do {
            guard let value = payload["sub"] as? String else {
                throw JWTAccessToken.ParseError.missingSubject
            }
            try JWTAccessToken.rejectEmptyOrControlCharacters(value)
            try JWTAccessToken.rejectEmptyOrControlCharacters(accessToken)
            subject = value
        } catch {
            throw AppError.unableToReadCodexSession
        }

        do {
            try JWTAccessToken.rejectIfExpired(payload: payload, now: now)
        } catch JWTAccessToken.ParseError.expired {
            throw AppError.sessionExpired
        }

        return CodexSession(
            accessToken: accessToken,
            accountID: try resolvedAccountID(accountID, payload: payload),
            subject: subject,
            accountFingerprint: JWTAccessToken.fingerprint(for: subject)
        )
    }

    static func credentials(from data: Data) throws -> (accessToken: String, accountID: String?) {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppError.unableToReadCodexSession
            }
            object = parsed
        } catch {
            throw AppError.unableToReadCodexSession
        }

        // API-key-only logins have no `tokens` object. They authenticate against
        // the OpenAI platform rather than a ChatGPT plan, so they have no
        // subscription window to report.
        guard let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty
        else {
            throw AppError.codexLoginNotFound
        }

        do {
            try JWTAccessToken.rejectEmptyOrControlCharacters(accessToken)
        } catch {
            throw AppError.unableToReadCodexSession
        }

        return (accessToken, tokens["account_id"] as? String)
    }

    /// The usage endpoint scopes the lookup with `ChatGPT-Account-Id`. Codex
    /// stores it alongside the tokens, but older logins only carry it inside the
    /// access token claims.
    private static func resolvedAccountID(
        _ storedAccountID: String?,
        payload: [String: Any]
    ) throws -> String? {
        let candidate = storedAccountID ?? claimedAccountID(in: payload)
        guard let candidate, !candidate.isEmpty else { return nil }
        do {
            try JWTAccessToken.rejectEmptyOrControlCharacters(candidate)
        } catch {
            throw AppError.unableToReadCodexSession
        }
        return candidate
    }

    private static func claimedAccountID(in payload: [String: Any]) -> String? {
        let authClaim = payload["https://api.openai.com/auth"] as? [String: Any]
        return authClaim?["chatgpt_account_id"] as? String
    }
}
