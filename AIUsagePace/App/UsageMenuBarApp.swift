import Foundation
import SwiftUI

@main
@MainActor
struct UsageMenuBarApp: App {
    @StateObject private var refreshService: RefreshService
    @StateObject private var languageSettings: LanguageSettings

    init() {
        let languageSettings = LanguageSettings()
        _languageSettings = StateObject(wrappedValue: languageSettings)

        let service = RefreshService(
            providers: [
                CursorUsageProvider(),
                GrokUsageProvider(),
            ],
            history: UsageHistoryStore()
        )
        _refreshService = StateObject(wrappedValue: service)
        if ProcessInfo.processInfo.environment["AI_USAGE_PACE_DISABLE_AUTOSTART"] != "1" {
            service.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(refreshService: refreshService)
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
        } label: {
            let title = refreshService.menuBarTitle(locale: languageSettings.locale)
            if title == UsageSnapshot.defaultMenuBarTitle {
                Text(LocalizedStringKey(LocalizationKey.menuUsagePace))
                    .environment(\.locale, languageSettings.locale)
            } else {
                Text(verbatim: title)
                    .environment(\.locale, languageSettings.locale)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
        }
    }
}
