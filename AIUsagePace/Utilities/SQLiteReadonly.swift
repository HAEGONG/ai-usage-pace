import Foundation
import SQLite3

enum SQLiteReadonly {
    private static let busyTimeoutMilliseconds: Int32 = 250
    private static let maxAttempts = 3
    private static let retryDelayNanoseconds: UInt64 = 50_000_000

    static func readString(databasePath: URL, sql: String) async throws -> String? {
        for attempt in 1...maxAttempts {
            do {
                return try readOnce(databasePath: databasePath, sql: sql)
            } catch SQLiteReadFailure.busy {
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    continue
                }
                throw AppError.unableToReadCursorSession
            } catch let error as AppError {
                throw error
            }
        }

        throw AppError.unableToReadCursorSession
    }

    private static func readOnce(databasePath: URL, sql: String) throws -> String? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databasePath.path, &database, flags, nil)
        guard openResult == SQLITE_OK, let database else {
            sqlite3_close(database)
            if isBusy(openResult) {
                throw SQLiteReadFailure.busy
            }
            throw AppError.unableToReadCursorSession
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            if isBusy(prepareResult) {
                throw SQLiteReadFailure.busy
            }
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
            if isBusy(step) {
                throw SQLiteReadFailure.busy
            }
            throw AppError.unableToReadCursorSession
        }
    }

    private static func isBusy(_ result: Int32) -> Bool {
        let primaryResult = result & 0xFF
        return primaryResult == SQLITE_BUSY || primaryResult == SQLITE_LOCKED
    }
}

private enum SQLiteReadFailure: Error {
    case busy
}
