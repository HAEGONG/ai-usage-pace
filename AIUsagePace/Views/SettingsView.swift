import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var languageSettings: LanguageSettings

    var body: some View {
        Form {
            Section(LocalizedStringKey(LocalizationKey.settingsLanguage)) {
                Picker(LocalizedStringKey(LocalizationKey.settingsLanguage), selection: $languageSettings.selection) {
                    Text(LocalizedStringKey(LocalizationKey.settingsLanguageSystem))
                        .tag(AppLanguage.system)
                    Text(LocalizedStringKey(LocalizationKey.settingsLanguageEnglish))
                        .tag(AppLanguage.english)
                    Text(LocalizedStringKey(LocalizationKey.settingsLanguageKorean))
                        .tag(AppLanguage.korean)
                }
                .labelsHidden()
            }
            Section(LocalizedStringKey(LocalizationKey.settingsRefresh)) {
                Text(LocalizedStringKey(LocalizationKey.settingsRefreshDescription))
            }
            Section(LocalizedStringKey(LocalizationKey.settingsDataSources)) {
                Text(LocalizedStringKey(LocalizationKey.settingsCursorDescription))
                Text(LocalizedStringKey(LocalizationKey.settingsGrokBotDescription))
                Text(LocalizedStringKey(LocalizationKey.settingsGrokCLIDescription))
                Text(LocalizedStringKey(LocalizationKey.settingsCodexDescription))
            }
            Section(LocalizedStringKey(LocalizationKey.settingsPrivacy)) {
                Text(LocalizedStringKey(LocalizationKey.settingsPrivacyDescription))
                Text(LocalizedStringKey(LocalizationKey.settingsHistoryDescription))
            }
            Section(LocalizedStringKey(LocalizationKey.settingsAbout)) {
                Text(LocalizedStringKey(LocalizationKey.settingsAboutDescription))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 600)
    }
}
