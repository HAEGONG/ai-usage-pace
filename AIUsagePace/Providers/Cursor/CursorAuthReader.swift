import Foundation

struct CursorSession: Equatable, Sendable {
    let accessToken: String
    let userID: String
    let subject: String
    let accountFingerprint: String
}

protocol SessionLoading: Sendable {
    func loadSession() async throws -> CursorSession
}

struct CursorAuthReader: SessionLoading {
    static let accessTokenKey = "cursorAuth/accessToken"

    var databasePath: URL
    var now: @Sendable () -> Date

    init(
        databasePath: URL = CursorAuthReader.defaultDatabasePath,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.databasePath = databasePath
        self.now = now
    }

    static var defaultDatabasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    func loadSession() async throws -> CursorSession {
        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            throw AppError.cursorNotInstalled
        }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        guard let accessToken = try await SQLiteReadonly.readString(databasePath: databasePath, sql: sql) else {
            throw AppError.cursorLoginNotFound
        }

        return try Self.session(fromAccessToken: accessToken, now: now())
    }

    static func session(fromAccessToken accessToken: String, now: Date) throws -> CursorSession {
        let payload: [String: Any]
        do {
            payload = try JWTAccessToken.payload(accessToken)
        } catch {
            throw AppError.unableToReadCursorSession
        }

        let subject: String
        do {
            guard let value = payload["sub"] as? String else {
                throw JWTAccessToken.ParseError.missingSubject
            }
            try JWTAccessToken.rejectEmptyOrControlCharacters(value)
            subject = value
        } catch {
            throw AppError.unableToReadCursorSession
        }

        let userID = userID(fromSubject: subject)
        do {
            try JWTAccessToken.rejectEmptyOrControlCharacters(userID)
            try JWTAccessToken.rejectEmptyOrControlCharacters(accessToken)
        } catch {
            throw AppError.unableToReadCursorSession
        }

        do {
            try JWTAccessToken.rejectIfExpired(payload: payload, now: now)
        } catch JWTAccessToken.ParseError.expired {
            throw AppError.sessionExpired
        }

        return CursorSession(
            accessToken: accessToken,
            userID: userID,
            subject: subject,
            accountFingerprint: fingerprint(for: subject)
        )
    }

    static func cookieValue(userID: String, accessToken: String) throws -> String {
        do {
            try JWTAccessToken.rejectEmptyOrControlCharacters(userID)
            try JWTAccessToken.rejectEmptyOrControlCharacters(accessToken)
        } catch {
            throw AppError.unableToReadCursorSession
        }
        return "\(userID)%3A%3A\(accessToken)"
    }

    static func userID(fromSubject subject: String) -> String {
        if let separator = subject.lastIndex(of: "|") {
            return String(subject[subject.index(after: separator)...])
        }
        return subject
    }

    static func fingerprint(for subject: String) -> String {
        JWTAccessToken.fingerprint(for: subject)
    }
}
