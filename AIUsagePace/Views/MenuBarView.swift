import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var refreshService: RefreshService
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(refreshService.providerStates.enumerated()), id: \.element.id) { index, state in
                if index > 0 {
                    Divider()
                }
                providerSection(state)
            }

            if refreshService.providerStates.allSatisfy({ $0.snapshot == nil && $0.error == nil }) {
                Text(LocalizedStringKey(LocalizationKey.menuLoadingUsage))
                    .foregroundStyle(.secondary)
            }

            Divider()
            Button(LocalizedStringKey(LocalizationKey.menuRefresh)) {
                refreshService.refresh()
            }
            SettingsLink {
                Text(LocalizedStringKey(LocalizationKey.menuSettings))
            }
            Button(LocalizedStringKey(LocalizationKey.menuQuit)) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private func providerSection(_ state: ProviderUsageState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasRedundantProviderHeading(state) {
                HStack(spacing: 6) {
                    ProviderIcon(providerID: state.providerID)
                    Text(LocalizedStringKey(LocalizationKey.provider(state.providerID)))
                }
                .font(.headline)
            }

            if let snapshot = state.snapshot {
                ProviderUsageView(snapshot: snapshot, stats: state.stats)
            }

            if let error = state.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(error.errorDescriptionLocalizationKey))
                        .foregroundStyle(.red)
                        .font(.callout)
                    if let recoveryKey = error.recoverySuggestionLocalizationKey {
                        Text(LocalizedStringKey(recoveryKey))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    if state.snapshot != nil {
                        Text(LocalizedStringKey(LocalizationKey.menuShowingLastAvailableUsage))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            if let warning = state.historyWarning {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(warning.errorDescriptionLocalizationKey))
                        .foregroundStyle(.orange)
                        .font(.callout)
                    if let recoveryKey = warning.recoverySuggestionLocalizationKey {
                        Text(LocalizedStringKey(recoveryKey))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            if let lastUpdated = state.lastUpdated {
                TimelineView(.periodic(from: lastUpdated, by: 1)) { context in
                    Text(verbatim: AppLocalization.format(
                        LocalizationKey.menuUpdated,
                        locale: locale,
                        arguments: [
                            AppLocalization.relativeDate(
                                lastUpdated,
                                relativeTo: context.date,
                                locale: locale
                            )
                        ],
                        defaultValue: "Updated %@"
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hasRedundantProviderHeading(_ state: ProviderUsageState) -> Bool {
        guard state.providerID == "grok", let snapshot = state.snapshot else {
            return false
        }
        let displayedPools = Set(snapshot.buckets.map(\.id))
            .union(snapshot.poolErrors.keys)
        return displayedPools == [.grokWeekly]
    }
}
