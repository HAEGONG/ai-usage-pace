import Foundation

enum AppLocalization {
    static func string(
        for key: String,
        locale: Locale,
        defaultValue: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let localizedBundle = bundle.path(forResource: languageCode, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? bundle
        return localizedBundle.localizedString(
            forKey: key,
            value: defaultValue ?? key,
            table: nil
        )
    }

    static func format(
        _ key: String,
        locale: Locale,
        arguments: [CVarArg],
        defaultValue: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        let template = string(
            for: key,
            locale: locale,
            defaultValue: defaultValue,
            bundle: bundle
        )
        return String(format: template, locale: locale, arguments: arguments)
    }

    static func relativeDate(_ date: Date, relativeTo referenceDate: Date = Date(), locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func dateTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func decimal(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }
}
