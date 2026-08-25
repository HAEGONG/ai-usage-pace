import AppKit
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
                CodexUsageProvider(),
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
            let locale = languageSettings.locale
            let title = refreshService.menuBarTitle(locale: locale)
            if title == UsageSnapshot.defaultMenuBarTitle {
                Text(LocalizedStringKey(LocalizationKey.menuUsagePace))
                    .environment(\.locale, locale)
            } else if let image = MenuBarStatusImage.make(
                iconName: refreshService.menuBarIconAssetName,
                title: title
            ) {
                Image(nsImage: image)
                    .accessibilityLabel(Text(verbatim: accessibilityLabel(percent: title, locale: locale)))
            } else {
                Text(verbatim: title)
                    .environment(\.locale, locale)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
        }
    }

    private func accessibilityLabel(percent: String, locale: Locale) -> String {
        guard let bucket = refreshService.highlightedBucket else {
            return percent
        }
        let poolTitle = AppLocalization.string(
            for: bucket.id.titleLocalizationKey,
            locale: locale,
            defaultValue: bucket.id.title
        )
        return "\(poolTitle) \(percent)"
    }
}

enum MenuBarStatusImage {
    private static let iconSide: CGFloat = 16
    private static let spacing: CGFloat = 3

    static func make(iconName: String?, title: String) -> NSImage? {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
            weight: .regular
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let hasIcon = iconName.flatMap { NSImage(named: $0) } != nil
        let width = (hasIcon ? iconSide + spacing : 0) + ceil(textSize.width)
        let height = max(iconSide, ceil(textSize.height))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            var x: CGFloat = 0
            if let iconName, let source = NSImage(named: iconName) {
                source.draw(
                    in: NSRect(
                        x: 0,
                        y: (rect.height - iconSide) / 2,
                        width: iconSide,
                        height: iconSide
                    )
                )
                x = iconSide + spacing
            }
            (title as NSString).draw(
                at: NSPoint(x: x, y: (rect.height - textSize.height) / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
