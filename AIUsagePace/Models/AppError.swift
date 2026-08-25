import Foundation

enum AppError: Error, Equatable, Sendable, CaseIterable {
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
    var errorDescriptionLocalizationKey: String {
        switch self {
        case .cursorNotInstalled:
            "error.cursor_not_installed"
        case .cursorLoginNotFound:
            "error.cursor_login_not_found"
        case .grokLoginNotFound:
            "error.grok_login_not_found"
        case .sessionExpired:
            "error.session_expired"
        case .unableToReadCursorSession:
            "error.unable_to_read_cursor_session"
        case .unableToReadGrokSession:
            "error.unable_to_read_grok_session"
        case .unsupportedAccountType:
            "error.unsupported_account_type"
        case .unsupportedResponseSchema:
            "error.unsupported_response_schema"
        case .usageUnavailable:
            "error.usage_unavailable"
        case .networkFailure:
            "error.network_failure"
        case .authenticationExpired:
            "error.authentication_expired"
        case .usageHistoryUnavailable:
            "error.usage_history_unavailable"
        }
    }

    var errorDescription: String? {
        switch self {
        case .cursorNotInstalled:
            "Cursor is not installed"
        case .cursorLoginNotFound:
            "Cursor login not found"
        case .grokLoginNotFound:
            "Grok CLI login not found"
        case .sessionExpired:
            "Session expired"
        case .unableToReadCursorSession:
            "Unable to read Cursor session"
        case .unableToReadGrokSession:
            "Unable to read Grok CLI session"
        case .unsupportedAccountType:
            "Unsupported account type"
        case .unsupportedResponseSchema:
            "Usage data format changed"
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

    var recoverySuggestionLocalizationKey: String? {
        switch self {
        case .cursorNotInstalled:
            "recovery.cursor_not_installed"
        case .cursorLoginNotFound:
            "recovery.cursor_login_not_found"
        case .grokLoginNotFound, .unableToReadGrokSession:
            "recovery.grok_login"
        case .sessionExpired, .authenticationExpired:
            "recovery.sign_in_again"
        case .unableToReadCursorSession:
            "recovery.unable_to_read_cursor_session"
        case .unsupportedAccountType:
            "recovery.unsupported_account_type"
        case .unsupportedResponseSchema:
            "recovery.unsupported_response_schema"
        case .usageUnavailable:
            "recovery.usage_unavailable"
        case .networkFailure:
            "recovery.network_failure"
        case .usageHistoryUnavailable:
            "recovery.usage_history_unavailable"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cursorNotInstalled:
            "Install Cursor, sign in, then refresh."
        case .cursorLoginNotFound:
            "Open Cursor and sign in, then refresh."
        case .grokLoginNotFound, .unableToReadGrokSession:
            "Run grok login, then click Refresh."
        case .sessionExpired, .authenticationExpired:
            "Sign in again, then refresh."
        case .unableToReadCursorSession:
            "If Cursor is open, wait a moment and refresh."
        case .unsupportedAccountType:
            "This account or plan is not supported."
        case .unsupportedResponseSchema:
            "The service returned usage data this version cannot read. Check for an app update."
        case .usageUnavailable:
            "Quota information was missing."
        case .networkFailure:
            "Check your connection and try again."
        case .usageHistoryUnavailable:
            "Current usage is available, but usage history could not be saved or loaded."
        }
    }
}
