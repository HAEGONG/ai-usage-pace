import CryptoKit
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
    static let sessionExpiryLeeway: TimeInterval = 60

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
        guard let accessToken = try SQLiteReadonly.readString(databasePath: databasePath, sql: sql) else {
            throw AppError.cursorLoginNotFound
        }

        return try Self.session(fromAccessToken: accessToken, now: now())
    }

    static func session(fromAccessToken accessToken: String, now: Date) throws -> CursorSession {
        let payload = try jwtPayload(accessToken)
        guard let subject = payload["sub"] as? String else {
            throw AppError.unableToReadCursorSession
        }
        try rejectEmptyOrControlCharacters(subject)

        let userID = userID(fromSubject: subject)
        try rejectEmptyOrControlCharacters(userID)

        if let expiration = payload["exp"] as? Double {
            let expiry = Date(timeIntervalSince1970: expiration)
            if expiry.timeIntervalSince(now) <= sessionExpiryLeeway {
                throw AppError.sessionExpired
            }
        } else if let expiration = payload["exp"] as? Int {
            let expiry = Date(timeIntervalSince1970: TimeInterval(expiration))
            if expiry.timeIntervalSince(now) <= sessionExpiryLeeway {
                throw AppError.sessionExpired
            }
        }

        return CursorSession(
            accessToken: accessToken,
            userID: userID,
            subject: subject,
            accountFingerprint: fingerprint(for: subject)
        )
    }

    static func cookieValue(userID: String, accessToken: String) throws -> String {
        try rejectEmptyOrControlCharacters(userID)
        try rejectEmptyOrControlCharacters(accessToken)
        return "\(userID)%3A%3A\(accessToken)"
    }

    static func userID(fromSubject subject: String) -> String {
        if let separator = subject.lastIndex(of: "|") {
            return String(subject[subject.index(after: separator)...])
        }
        return subject
    }

    static func fingerprint(for subject: String) -> String {
        let digest = SHA256.hash(data: Data(subject.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func jwtPayload(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw AppError.unableToReadCursorSession
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AppError.unableToReadCursorSession
        }
        return json
    }

    private static func rejectEmptyOrControlCharacters(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.unableToReadCursorSession
        }
        let hasControl = value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        if hasControl {
            throw AppError.unableToReadCursorSession
        }
    }
}
