import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case english = "en"
    case korean = "ko"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    func locale(systemLocale: Locale = .current) -> Locale {
        switch self {
        case .system:
            let languageCode = systemLocale.language.languageCode?.identifier
            return Locale(identifier: languageCode == "ko" ? "ko" : "en")
        case .english:
            return Locale(identifier: "en")
        case .korean:
            return Locale(identifier: "ko")
        }
    }
}

enum LocalizationKey {
    static let settingsRefresh = "settings.refresh"
    static let settingsRefreshDescription = "settings.refresh.description"
    static let settingsDataSources = "settings.data_sources"
    static let settingsCursorDescription = "settings.cursor_description"
    static let settingsGrokBotDescription = "settings.grok_bot_description"
    static let settingsGrokCLIDescription = "settings.grok_cli_description"
    static let settingsPrivacy = "settings.privacy"
    static let settingsPrivacyDescription = "settings.privacy.description"
    static let settingsHistoryDescription = "settings.history.description"
    static let settingsAbout = "settings.about"
    static let settingsAboutDescription = "settings.about.description"
    static let settingsLanguage = "settings.language"
    static let settingsLanguageSystem = "settings.language.system"
    static let settingsLanguageEnglish = "settings.language.english"
    static let settingsLanguageKorean = "settings.language.korean"

    static let menuLoadingUsage = "menu.loading_usage"
    static let menuRefresh = "menu.refresh"
    static let menuSettings = "menu.settings"
    static let menuQuit = "menu.quit"
    static let menuUsagePace = "menu.usage_pace"
    static let menuShowingLastAvailableUsage = "menu.showing_last_available_usage"
    static let menuUpdated = "menu.updated"

    static let providerCursor = "provider.cursor"
    static let providerGrokCLI = "provider.grok_cli"

    static let usageCursorModels = "usage.pool.cursor_models"
    static let usageOtherModels = "usage.pool.other_models"
    static let usageGrokBot = "usage.pool.grok_bot"
    static let usageGrokCLI = "usage.pool.grok_cli"
    static let usagePoolError = "usage.pool_error"
    static let usageUsedToday = "usage.used_today"
    static let usagePace = "usage.pace"
    static let usageRunsOut = "usage.runs_out"
    static let usageResets = "usage.resets"
    static let usageCollectingData = "usage.collecting_data"
    static let usageAtLimit = "usage.at_limit"
    static let usageWaitingForReset = "usage.waiting_for_reset"
    static let usageLikelyWontRunOut = "usage.likely_wont_run_out"
    static let usageNotExpectedToRunOut = "usage.not_expected_to_run_out"
    static let usageSinceFirstCheckToday = "usage.since_first_check_today"
    static let usageLowConfidence = "usage.low_confidence"

    static func provider(_ id: String) -> String {
        switch id {
        case "cursor": providerCursor
        case "grok": providerGrokCLI
        default: "provider.\(id)"
        }
    }
}
