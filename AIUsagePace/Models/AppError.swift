import Foundation

enum AppError: Error, Equatable, Sendable {
    case cursorNotInstalled
    case cursorLoginNotFound
    case grokLoginNotFound
    case sessionExpired
    case unableToReadCursorSession
    case unableToReadGrokSession
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
        case .grokLoginNotFound:
            "Grok login not found"
        case .sessionExpired:
            "Session expired"
        case .unableToReadCursorSession:
            "Unable to read Cursor session"
        case .unableToReadGrokSession:
            "Unable to read Grok session"
        case .unsupportedAccountType:
            "Unsupported account type"
        case .unsupportedResponseSchema:
            "Usage response changed"
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
        case .cursorLoginNotFound:
            "Open Cursor and sign in, then refresh."
        case .grokLoginNotFound, .unableToReadGrokSession:
            "Run grok login, then refresh."
        case .sessionExpired, .authenticationExpired:
            "Sign in again, then refresh."
        case .unableToReadCursorSession:
            "If Cursor is open, wait a moment and refresh."
        case .unsupportedAccountType:
            "Team, Enterprise, Business, unlimited, and non-weekly Grok plans are not supported."
        case .unsupportedResponseSchema:
            "The unofficial usage response is no longer recognized."
        case .usageUnavailable:
            "Quota information was missing."
        case .networkFailure:
            "Check your connection and try again."
        case .usageHistoryUnavailable:
            "Current usage is available, but pace history could not be saved or loaded."
        }
    }
}
