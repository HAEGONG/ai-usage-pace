import Combine
import Foundation

@MainActor
final class LanguageSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var selection: AppLanguage {
        didSet {
            defaults.set(selection.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawValue = defaults.string(forKey: AppLanguage.storageKey)
        self.selection = AppLanguage(rawValue: rawValue ?? "") ?? .system
        if rawValue != selection.rawValue {
            defaults.set(selection.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    var locale: Locale {
        selection.locale()
    }
}
