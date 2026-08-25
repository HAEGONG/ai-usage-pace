import XCTest
@testable import AIUsagePace

final class AppLanguageTests: XCTestCase {
    @MainActor
    func testRawValuesAndLocaleResolution() {
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.korean.rawValue, "ko")

        XCTAssertEqual(AppLanguage.english.locale().language.languageCode?.identifier, "en")
        XCTAssertEqual(AppLanguage.korean.locale().language.languageCode?.identifier, "ko")
        XCTAssertEqual(
            AppLanguage.system.locale(systemLocale: Locale(identifier: "ko-KR")).language.languageCode?.identifier,
            "ko"
        )
        XCTAssertEqual(
            AppLanguage.system.locale(systemLocale: Locale(identifier: "fr-FR")).language.languageCode?.identifier,
            "en"
        )
    }

    @MainActor
    func testLanguageSettingsDefaultsAndPersistsSelection() {
        let suiteName = "AIUsagePace.AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = LanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.selection, .system)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "system")

        settings.selection = .korean
        XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "ko")
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .korean)

        defaults.set("not-supported", forKey: AppLanguage.storageKey)
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .system)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "system")
    }

    func testCatalogContainsReferencedKeysInEnglishAndKorean() {
        let bundle = Bundle(for: AppLanguageTests.self)
        let keys = [
            LocalizationKey.settingsRefresh,
            LocalizationKey.settingsRefreshDescription,
            LocalizationKey.settingsDataSources,
            LocalizationKey.settingsCursorDescription,
            LocalizationKey.settingsGrokBotDescription,
            LocalizationKey.settingsGrokCLIDescription,
            LocalizationKey.settingsCodexDescription,
            LocalizationKey.settingsPrivacy,
            LocalizationKey.settingsPrivacyDescription,
            LocalizationKey.settingsHistoryDescription,
            LocalizationKey.settingsAbout,
            LocalizationKey.settingsAboutDescription,
            LocalizationKey.settingsLanguage,
            LocalizationKey.settingsLanguageSystem,
            LocalizationKey.settingsLanguageEnglish,
            LocalizationKey.settingsLanguageKorean,
            LocalizationKey.menuLoadingUsage,
            LocalizationKey.menuRefresh,
            LocalizationKey.menuSettings,
            LocalizationKey.menuQuit,
            LocalizationKey.menuUsagePace,
            LocalizationKey.menuShowingLastAvailableUsage,
            LocalizationKey.menuUpdated,
            LocalizationKey.providerCursor,
            LocalizationKey.providerGrokCLI,
            LocalizationKey.providerCodex,
            LocalizationKey.usageCursorModels,
            LocalizationKey.usageOtherModels,
            LocalizationKey.usageGrokBot,
            LocalizationKey.usageGrokCLI,
            LocalizationKey.usageCodexSession,
            LocalizationKey.usageCodexWeekly,
            LocalizationKey.usagePoolError,
            LocalizationKey.usageUsedToday,
            LocalizationKey.usagePace,
            LocalizationKey.usageRunsOut,
            LocalizationKey.usageResets,
            LocalizationKey.usageNoComparisonYet,
            LocalizationKey.usageNotEnoughHistory,
            LocalizationKey.usageAtLimit,
            LocalizationKey.usageWaitingForReset,
            LocalizationKey.usageLikelyWontRunOut,
            LocalizationKey.usageNotExpectedToRunOut,
            LocalizationKey.usageSinceFirstCheckToday,
            LocalizationKey.usageLowConfidence,
            LocalizationKey.usagePaceDetailsTitle,
            LocalizationKey.usagePaceDetailsConfidence,
            LocalizationKey.usagePaceDetailsConfidenceLow,
            LocalizationKey.usagePaceDetailsConfidenceMedium,
            LocalizationKey.usagePaceDetailsConfidenceHigh,
            LocalizationKey.usagePaceDetailsCalculation,
            LocalizationKey.usagePaceDetailsFormula,
            LocalizationKey.usagePaceDetailsMonthlyMethod,
            LocalizationKey.usagePaceDetailsWeeklyMethod,
            LocalizationKey.usagePaceDetailsObservation,
            LocalizationKey.usagePaceDetailsHistoryCycles,
            LocalizationKey.usagePaceDetailsMoreObservation,
            LocalizationKey.usagePaceDetailsAmbiguousGap,
            LocalizationKey.usagePaceDetailsUnstableHistory,
            LocalizationKey.usagePaceDetailsProvisionalEstimate,
            LocalizationKey.usagePaceDetailsDurationHours,
            LocalizationKey.usagePaceDetailsDurationDaysHours,
            LocalizationKey.usagePaceDetailsDefinition,
            LocalizationKey.usagePaceDetailsAccessibilityHint,
            LocalizationKey.usageRunsOutDetailsTitle,
            LocalizationKey.usageRunsOutDetailsFormula,
            LocalizationKey.usageRunsOutDetailsProjection,
            LocalizationKey.usageRunsOutDetailsDefinition,
        ]
        let errorDescriptionKeys = AppError.allCases.map(\.errorDescriptionLocalizationKey)
        let recoveryKeys = AppError.allCases.compactMap(\.recoverySuggestionLocalizationKey)
        let poolTitleKeys = UsagePoolID.allCases.map(\.titleLocalizationKey)

        XCTAssertEqual(Set(keys).count, keys.count, "LocalizationKey constants must be distinct")
        XCTAssertEqual(errorDescriptionKeys.count, AppError.allCases.count)
        XCTAssertEqual(
            Set(errorDescriptionKeys).count,
            errorDescriptionKeys.count,
            "AppError description keys must be complete and distinct"
        )
        XCTAssertTrue(errorDescriptionKeys.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(poolTitleKeys.count, UsagePoolID.allCases.count)
        XCTAssertEqual(
            Set(poolTitleKeys).count,
            poolTitleKeys.count,
            "UsagePoolID title keys must be complete and distinct"
        )
        XCTAssertTrue(poolTitleKeys.allSatisfy { !$0.isEmpty })

        for key in keys + errorDescriptionKeys + recoveryKeys + poolTitleKeys {
            let english = AppLocalization.string(for: key, locale: Locale(identifier: "en"), bundle: bundle)
            let korean = AppLocalization.string(for: key, locale: Locale(identifier: "ko"), bundle: bundle)
            XCTAssertNotEqual(english, key, "Missing English catalog entry for \(key)")
            XCTAssertNotEqual(korean, key, "Missing Korean catalog entry for \(key)")
        }
    }

    func testUsagePaceBrandRemainsUntranslated() {
        let bundle = Bundle(for: AppLanguageTests.self)
        XCTAssertEqual(
            AppLocalization.string(for: LocalizationKey.menuUsagePace, locale: Locale(identifier: "en"), bundle: bundle),
            "Usage Pace"
        )
        XCTAssertEqual(
            AppLocalization.string(for: LocalizationKey.menuUsagePace, locale: Locale(identifier: "ko"), bundle: bundle),
            "Usage Pace"
        )
    }

    func testInitialUsageStatusWording() {
        let bundle = Bundle(for: AppLanguageTests.self)
        XCTAssertEqual(
            AppLocalization.string(
                for: LocalizationKey.usageNoComparisonYet,
                locale: Locale(identifier: "en"),
                bundle: bundle
            ),
            "No comparison yet"
        )
        XCTAssertEqual(
            AppLocalization.string(
                for: LocalizationKey.usageNoComparisonYet,
                locale: Locale(identifier: "ko"),
                bundle: bundle
            ),
            "아직 비교 기록 없음"
        )
        XCTAssertEqual(
            AppLocalization.string(
                for: LocalizationKey.usageNotEnoughHistory,
                locale: Locale(identifier: "en"),
                bundle: bundle
            ),
            "Not enough usage history"
        )
        XCTAssertEqual(
            AppLocalization.string(
                for: LocalizationKey.usageNotEnoughHistory,
                locale: Locale(identifier: "ko"),
                bundle: bundle
            ),
            "사용 기록 부족"
        )
    }

    func testCatalogPreservesDynamicSentenceOrder() {
        let bundle = Bundle(for: AppLanguageTests.self)
        XCTAssertEqual(
            AppLocalization.format(
                LocalizationKey.usageSinceFirstCheckToday,
                locale: Locale(identifier: "ko"),
                arguments: ["+1.0%"],
                bundle: bundle
            ),
            "오늘 첫 확인 이후 +1.0%"
        )
        XCTAssertEqual(
            AppLocalization.format(
                LocalizationKey.menuUpdated,
                locale: Locale(identifier: "ko"),
                arguments: ["5분 전"],
                bundle: bundle
            ),
            "5분 전 업데이트"
        )
        XCTAssertEqual(
            AppLocalization.format(
                LocalizationKey.usagePoolError,
                locale: Locale(identifier: "ko"),
                arguments: ["Cursor 모델", "사용량을 가져올 수 없습니다"],
                bundle: bundle
            ),
            "Cursor 모델: 사용량을 가져올 수 없습니다"
        )
    }

    func testLocaleAwareUsageFormattingKeepsTheRenderedNumber() {
        XCTAssertEqual(
            UsagePercentFormat.string(42.5, locale: Locale(identifier: "en")),
            "42.5%"
        )
    }

    func testRelativeDateAdvancesWithTheReferenceDate() {
        let korean = Locale(identifier: "ko")
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        XCTAssertEqual(
            AppLocalization.relativeDate(now.addingTimeInterval(-5), relativeTo: now, locale: korean),
            "5초 전"
        )
        XCTAssertEqual(
            AppLocalization.relativeDate(now.addingTimeInterval(-59), relativeTo: now, locale: korean),
            "59초 전"
        )
        XCTAssertEqual(
            AppLocalization.relativeDate(now.addingTimeInterval(-120), relativeTo: now, locale: korean),
            "2분 전"
        )
        XCTAssertEqual(
            AppLocalization.format(
                LocalizationKey.menuUpdated,
                locale: korean,
                arguments: [
                    AppLocalization.relativeDate(now.addingTimeInterval(-5), relativeTo: now, locale: korean)
                ]
            ),
            "5초 전 업데이트"
        )
    }
}
