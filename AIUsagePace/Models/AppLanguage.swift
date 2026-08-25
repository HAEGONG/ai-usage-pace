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
    static let settingsCodexDescription = "settings.codex_description"
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
    static let providerCodex = "provider.codex"

    static let usageCursorModels = "usage.pool.cursor_models"
    static let usageOtherModels = "usage.pool.other_models"
    static let usageGrokBot = "usage.pool.grok_bot"
    static let usageGrokCLI = "usage.pool.grok_cli"
    static let usageCodexSession = "usage.pool.codex_session"
    static let usageCodexWeekly = "usage.pool.codex_weekly"
    static let usagePoolError = "usage.pool_error"
    static let usageUsedToday = "usage.used_today"
    static let usagePace = "usage.pace"
    static let usageRunsOut = "usage.runs_out"
    static let usageResets = "usage.resets"
    static let usageNoComparisonYet = "usage.no_comparison_yet"
    static let usageNotEnoughHistory = "usage.not_enough_history"
    static let usageAtLimit = "usage.at_limit"
    static let usageWaitingForReset = "usage.waiting_for_reset"
    static let usageLikelyWontRunOut = "usage.likely_wont_run_out"
    static let usageNotExpectedToRunOut = "usage.not_expected_to_run_out"
    static let usageSinceFirstCheckToday = "usage.since_first_check_today"
    static let usageLowConfidence = "usage.low_confidence"
    static let usagePaceDetailsTitle = "usage.pace_details.title"
    static let usagePaceDetailsConfidence = "usage.pace_details.confidence"
    static let usagePaceDetailsConfidenceLow = "usage.pace_details.confidence.low"
    static let usagePaceDetailsConfidenceMedium = "usage.pace_details.confidence.medium"
    static let usagePaceDetailsConfidenceHigh = "usage.pace_details.confidence.high"
    static let usagePaceDetailsCalculation = "usage.pace_details.calculation"
    static let usagePaceDetailsFormula = "usage.pace_details.formula"
    static let usagePaceDetailsMonthlyMethod = "usage.pace_details.monthly_method"
    static let usagePaceDetailsWeeklyMethod = "usage.pace_details.weekly_method"
    static let usagePaceDetailsObservation = "usage.pace_details.observation"
    static let usagePaceDetailsHistoryCycles = "usage.pace_details.history_cycles"
    static let usagePaceDetailsMoreObservation = "usage.pace_details.more_observation"
    static let usagePaceDetailsAmbiguousGap = "usage.pace_details.ambiguous_gap"
    static let usagePaceDetailsUnstableHistory = "usage.pace_details.unstable_history"
    static let usagePaceDetailsProvisionalEstimate = "usage.pace_details.provisional_estimate"
    static let usagePaceDetailsDurationHours = "usage.pace_details.duration.hours"
    static let usagePaceDetailsDurationDaysHours = "usage.pace_details.duration.days_hours"
    static let usagePaceDetailsDefinition = "usage.pace_details.definition"
    static let usagePaceDetailsAccessibilityHint = "usage.pace_details.accessibility_hint"
    static let usageRunsOutDetailsTitle = "usage.runs_out_details.title"
    static let usageRunsOutDetailsFormula = "usage.runs_out_details.formula"
    static let usageRunsOutDetailsProjection = "usage.runs_out_details.projection"
    static let usageRunsOutDetailsDefinition = "usage.runs_out_details.definition"

    static func provider(_ id: String) -> String {
        switch id {
        case "cursor": providerCursor
        case "grok": providerGrokCLI
        case "codex": providerCodex
        default: "provider.\(id)"
        }
    }
}
