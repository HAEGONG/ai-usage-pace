import Foundation
import SwiftUI

@main
@MainActor
struct UsageMenuBarApp: App {
    @StateObject private var refreshService: RefreshService

    init() {
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
        } label: {
            Text(refreshService.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
