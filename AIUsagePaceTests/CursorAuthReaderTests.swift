import Foundation
import SQLite3
import XCTest
@testable import AIUsagePace

final class CursorAuthReaderTests: XCTestCase {
    func testUserIDUsesTextAfterLastPipe() {
        XCTAssertEqual(CursorAuthReader.userID(fromSubject: "github|user_01ABC"), "user_01ABC")
        XCTAssertEqual(CursorAuthReader.userID(fromSubject: "user_01ABC"), "user_01ABC")
    }

    func testRejectsEmptyOrControlCharactersInSubject() {
        let expired = Date(timeIntervalSince1970: 4_000)
        XCTAssertThrowsError(
            try CursorAuthReader.session(fromAccessToken: syntheticJWT(sub: "github|\u{0007}bad", exp: 5_000), now: expired)
        ) { error in
            XCTAssertEqual(error as? AppError, .unableToReadCursorSession)
        }
    }

    func testExpiredTokenThrowsWithoutNeedingNetwork() {
        let token = syntheticJWT(sub: "github|user_01ABC", exp: 1_000)
        let now = Date(timeIntervalSince1970: 1_000 - 30)
        XCTAssertThrowsError(try CursorAuthReader.session(fromAccessToken: token, now: now)) { error in
            XCTAssertEqual(error as? AppError, .sessionExpired)
        }
    }

    func testValidTokenProducesFingerprint() throws {
        let token = syntheticJWT(sub: "github|user_01ABC", exp: 10_000)
        let session = try CursorAuthReader.session(
            fromAccessToken: token,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(session.userID, "user_01ABC")
        XCTAssertEqual(session.accountFingerprint.count, 64)
        XCTAssertFalse(session.accountFingerprint.contains(session.accessToken))
    }

    func testCookieEncodesSeparatorWithoutRawColons() throws {
        let cookie = try CursorAuthReader.cookieValue(userID: "user_01ABC", accessToken: "token.part")
        XCTAssertTrue(cookie.contains("%3A%3A"))
        XCTAssertFalse(cookie.contains("::"))
    }

    func testMissingDatabaseIsCursorNotInstalled() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).vscdb")
        let reader = CursorAuthReader(databasePath: missing)
        do {
            _ = try await reader.loadSession()
            XCTFail("Expected cursorNotInstalled")
        } catch {
            XCTAssertEqual(error as? AppError, .cursorNotInstalled)
        }
    }

    func testSyntheticSQLiteAccessTokenIsRead() async throws {
        let token = syntheticJWT(sub: "github|user_01ABC", exp: 10_000)
        let database = try sqliteFixture(accessToken: token)
        defer { try? FileManager.default.removeItem(at: database) }

        let reader = CursorAuthReader(
            databasePath: database,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let session = try await reader.loadSession()
        XCTAssertEqual(session.userID, "user_01ABC")
        XCTAssertEqual(session.accessToken, token)
    }

    func testMissingAccessTokenKeyIsCursorLoginNotFound() async throws {
        let database = try sqliteFixture(accessToken: nil)
        defer { try? FileManager.default.removeItem(at: database) }

        let reader = CursorAuthReader(databasePath: database)
        do {
            _ = try await reader.loadSession()
            XCTFail("Expected cursorLoginNotFound")
        } catch {
            XCTAssertEqual(error as? AppError, .cursorLoginNotFound)
        }
    }

    func testBusyDatabaseIsUnableToReadCursorSession() async throws {
        let database = try sqliteFixture(accessToken: syntheticJWT(sub: "github|user_01ABC", exp: 10_000))
        defer { try? FileManager.default.removeItem(at: database) }

        var locker: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(database.path, &locker, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(locker, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        defer {
            sqlite3_exec(locker, "ROLLBACK", nil, nil, nil)
            sqlite3_close(locker)
        }

        do {
            _ = try await SQLiteReadonly.readString(
                databasePath: database,
                sql: "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
            )
            XCTFail("Expected unableToReadCursorSession")
        } catch {
            XCTAssertEqual(error as? AppError, .unableToReadCursorSession)
        }
    }
}

func syntheticJWT(sub: String, exp: Int) -> String {
    let header = base64URL(["alg": "none", "typ": "JWT"])
    let payload = base64URL(["sub": sub, "exp": exp])
    return "\(header).\(payload).sig"
}

private func sqliteFixture(accessToken: String?) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cursor-state-\(UUID().uuidString).vscdb")
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw AppError.unableToReadCursorSession
    }
    defer { sqlite3_close(database) }

    guard sqlite3_exec(database, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);", nil, nil, nil) == SQLITE_OK else {
        throw AppError.unableToReadCursorSession
    }
    guard let accessToken else { return url }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO ItemTable (key, value) VALUES (?, ?);",
        -1,
        &statement,
        nil
    ) == SQLITE_OK, let statement else {
        throw AppError.unableToReadCursorSession
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, "cursorAuth/accessToken", -1, SQLITE_TRANSIENT)
    _ = accessToken.withCString { pointer in
        sqlite3_bind_text(statement, 2, pointer, -1, SQLITE_TRANSIENT)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw AppError.unableToReadCursorSession
    }
    return url
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func base64URL(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
