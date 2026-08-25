import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var refreshService: RefreshService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(refreshService.providerStates.enumerated()), id: \.element.id) { index, state in
                if index > 0 {
                    Divider()
                }
                providerSection(state)
            }

            if refreshService.providerStates.allSatisfy({ $0.snapshot == nil && $0.error == nil }) {
                Text("Waiting for usage")
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

    @ViewBuilder
    private func providerSection(_ state: ProviderUsageState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.displayName)
                .font(.headline)

            if let snapshot = state.snapshot {
                ProviderUsageView(snapshot: snapshot, stats: state.stats)
            }

            if let error = state.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.callout)
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    if state.snapshot != nil {
                        Text("Showing last successful update")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            if let warning = state.historyWarning {
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

            if let lastUpdated = state.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
