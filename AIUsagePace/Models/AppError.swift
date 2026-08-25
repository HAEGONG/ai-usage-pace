import Foundation

enum AppError: Error, Equatable, Sendable {
    case cursorNotInstalled
    case cursorLoginNotFound
    case sessionExpired
    case unableToReadCursorSession
    case unsupportedAccountType
    case unsupportedResponseSchema
    case usageUnavailable
    case networkFailure
    case authenticationExpired
    case usageHistoryUnavailable
}

extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cursorNotInstalled:
            "Cursor is not installed"
        case .cursorLoginNotFound:
            "Cursor login not found"
        case .sessionExpired:
            "Session expired"
        case .unableToReadCursorSession:
            "Unable to read Cursor session"
        case .unsupportedAccountType:
            "Unsupported account type"
        case .unsupportedResponseSchema:
            "Cursor usage response changed"
        case .usageUnavailable:
            "Usage data is unavailable"
        case .networkFailure:
            "Unable to fetch usage"
        case .authenticationExpired:
            "Authentication may have expired"
        case .usageHistoryUnavailable:
            "Usage history is unavailable"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cursorNotInstalled:
            "Install Cursor, sign in, then refresh."
        case .cursorLoginNotFound, .sessionExpired, .authenticationExpired:
            "Open Cursor and sign in, then refresh."
        case .unableToReadCursorSession:
            "If Cursor is open, wait a moment and refresh."
        case .unsupportedAccountType:
            "Team, Enterprise, Business, and unlimited plans are not supported."
        case .unsupportedResponseSchema:
            "The unofficial usage-summary shape is no longer recognized."
        case .usageUnavailable:
            "Quota information was missing from Cursor."
        case .networkFailure:
            "Check your connection and try again."
        case .usageHistoryUnavailable:
            "Current usage is available, but pace history could not be saved or loaded."
        }
    }
}
