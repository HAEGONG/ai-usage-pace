import Foundation

struct GrokSession: Equatable, Sendable {
    let accessToken: String
    let subject: String
    let accountFingerprint: String
}

struct GrokAuthReader: Sendable {
    var filePath: URL
    var now: @Sendable () -> Date

    init(
        filePath: URL = GrokAuthReader.defaultFilePath,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.filePath = filePath
        self.now = now
    }

    static var defaultFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    func loadSession() async throws -> GrokSession {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw AppError.grokLoginNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: filePath)
        } catch {
            throw AppError.unableToReadGrokSession
        }

        let token = try Self.accessToken(from: data)
        return try Self.session(fromAccessToken: token, now: now())
    }

    static func session(fromAccessToken accessToken: String, now: Date) throws -> GrokSession {
        let payload: [String: Any]
        do {
            payload = try JWTAccessToken.payload(accessToken)
        } catch {
            throw AppError.unableToReadGrokSession
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
            throw AppError.unableToReadGrokSession
        }

        do {
            try JWTAccessToken.rejectIfExpired(payload: payload, now: now)
        } catch JWTAccessToken.ParseError.expired {
            throw AppError.sessionExpired
        }

        return GrokSession(
            accessToken: accessToken,
            subject: subject,
            accountFingerprint: JWTAccessToken.fingerprint(for: subject)
        )
    }

    static func accessToken(from data: Data) throws -> String {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppError.unableToReadGrokSession
            }
            object = parsed
        } catch {
            throw AppError.unableToReadGrokSession
        }

        if let token = object["access_token"] as? String {
            return try requireToken(token)
        }

        var candidates: [String] = []
        for value in object.values {
            guard let entry = value as? [String: Any], let token = entry["key"] as? String else {
                continue
            }
            candidates.append(token)
        }

        guard let token = preferredAccessToken(candidates) else {
            throw AppError.grokLoginNotFound
        }
        return try requireToken(token)
    }

    private static func preferredAccessToken(_ tokens: [String]) -> String? {
        guard !tokens.isEmpty else { return nil }
        let ranked = tokens.sorted { lhs, rhs in
            (expiration(of: lhs) ?? .distantPast) > (expiration(of: rhs) ?? .distantPast)
        }
        if let valid = ranked.first(where: isUnexpired) {
            return valid
        }
        return ranked.first
    }

    private static func isUnexpired(_ token: String) -> Bool {
        guard let payload = try? JWTAccessToken.payload(token) else { return false }
        do {
            try JWTAccessToken.rejectIfExpired(payload: payload, now: Date())
            return true
        } catch {
            return false
        }
    }

    private static func expiration(of token: String) -> Date? {
        guard let payload = try? JWTAccessToken.payload(token) else { return nil }
        if let value = payload["exp"] as? Double {
            return Date(timeIntervalSince1970: value)
        }
        if let value = payload["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        return nil
    }

    private static func requireToken(_ token: String) throws -> String {
        do {
            try JWTAccessToken.rejectEmptyOrControlCharacters(token)
        } catch {
            throw AppError.unableToReadGrokSession
        }
        return token
    }
}
