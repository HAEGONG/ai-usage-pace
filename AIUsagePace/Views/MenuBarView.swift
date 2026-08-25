import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var refreshService: RefreshService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = refreshService.displayedSnapshot {
                ProviderUsageView(snapshot: snapshot, stats: refreshService.stats)
            }

            if let error = refreshService.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.callout)
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    if refreshService.displayedSnapshot != nil {
                        Text("Showing last successful update")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            } else if refreshService.displayedSnapshot == nil {
                Text("Waiting for usage")
                    .foregroundStyle(.secondary)
            }

            if let warning = refreshService.historyWarning {
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.localizedDescription)
                        .foregroundStyle(.orange)
                        .font(.callout)
                    if let recovery = warning.recoverySuggestion {
                        Text(recovery)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            if let lastUpdated = refreshService.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Button("Refresh") {
                refreshService.refresh()
            }
            SettingsLink {
                Text("Settings…")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
    }
}
