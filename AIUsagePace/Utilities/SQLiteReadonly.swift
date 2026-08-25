import Foundation
import SQLite3

enum SQLiteReadonly {
    private static let busyTimeoutMilliseconds: Int32 = 250
    private static let maxAttempts = 3

    static func readString(databasePath: URL, sql: String) throws -> String? {
        var lastError: AppError = .unableToReadCursorSession

        for attempt in 1...maxAttempts {
            do {
                return try readOnce(databasePath: databasePath, sql: sql)
            } catch let error as AppError {
                lastError = error
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
            }
        }

        throw lastError
    }

    private static func readOnce(databasePath: URL, sql: String) throws -> String? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath.path, &database, flags, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw AppError.unableToReadCursorSession
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AppError.unableToReadCursorSession
        }
        defer { sqlite3_finalize(statement) }

        let step = sqlite3_step(statement)
        switch step {
        case SQLITE_ROW:
            guard let cString = sqlite3_column_text(statement, 0) else {
                return nil
            }
            let value = String(cString: cString)
            return value.isEmpty ? nil : value
        case SQLITE_DONE:
            return nil
        default:
            throw AppError.unableToReadCursorSession
        }
    }
}
