import SwiftUI

struct ProviderUsageView: View {
    let snapshot: UsageSnapshot
    var stats: UsageStats?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(snapshot.buckets, id: \.id) { bucket in
                PoolUsageRow(bucket: bucket, stats: stats?.pools[bucket.id])
            }

            ForEach(poolErrorIDs, id: \.self) { pool in
                if let error = snapshot.poolErrors[pool] {
                    poolErrorView(pool: pool, error: error)
                }
            }
        }
    }

    private var poolErrorIDs: [UsagePoolID] {
        snapshot.poolErrors.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private func poolErrorView(pool: UsagePoolID, error: AppError) -> some View {
        let poolTitle = AppLocalization.string(
            for: pool.titleLocalizationKey,
            locale: locale,
            defaultValue: pool.title
        )
        let errorDescription = AppLocalization.string(
            for: error.errorDescriptionLocalizationKey,
            locale: locale,
            defaultValue: error.errorDescription ?? ""
        )
        let message = AppLocalization.format(
            LocalizationKey.usagePoolError,
            locale: locale,
            arguments: [poolTitle, errorDescription],
            defaultValue: "%1$@: %2$@"
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: message)
                .foregroundStyle(.red)
                .font(.callout)
            if let recoveryKey = error.recoverySuggestionLocalizationKey {
                Text(LocalizedStringKey(recoveryKey))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private struct PoolUsageRow: View {
    let bucket: UsageBucket
    var stats: PoolStats?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(bucket.id.titleLocalizationKey))
                    .font(.headline)
                Spacer()
                Text(verbatim: UsagePercentFormat.string(bucket.percentUsed, locale: locale))
                    .font(.headline)
                    .monospacedDigit()
            }
            ProgressView(value: bucket.progressFraction)
            metric(LocalizationKey.usageUsedToday, todayText)
            metric(LocalizationKey.usagePace, paceText)
            metric(LocalizationKey.usageRunsOut, exhaustionText)
            if let cycleEnd = bucket.cycleEnd {
                metric(LocalizationKey.usageResets, AppLocalization.dateTime(cycleEnd, locale: locale))
            }
        }
    }

    private var todayText: String {
        guard let delta = stats?.todayDelta else {
            return localized(LocalizationKey.usageCollectingData, defaultValue: "Collecting data…")
        }
        let value = signedDecimal(delta)
        if stats?.todayIsSinceFirstRecord == true {
            return AppLocalization.format(
                LocalizationKey.usageSinceFirstCheckToday,
                locale: locale,
                arguments: [value],
                defaultValue: "%@ since first check today"
            )
        }
        return value
    }

    private var paceText: String {
        switch stats?.message {
        case .atLimit:
            return localized(LocalizationKey.usageAtLimit, defaultValue: "At limit")
        case .resetPending:
            return localized(LocalizationKey.usageWaitingForReset, defaultValue: "Waiting for reset")
        case .notEnoughData, nil:
            return localized(LocalizationKey.usageCollectingData, defaultValue: "Collecting data…")
        case .ready, .resetsBeforeExhaustion, .noExhaustionProjected:
            if let ratio = stats?.paceRatio {
                let value = AppLocalization.decimal(ratio, fractionDigits: 1, locale: locale) + "×"
                if stats?.lowConfidence == true {
                    return AppLocalization.format(
                        LocalizationKey.usageLowConfidence,
                        locale: locale,
                        arguments: [value],
                        defaultValue: "%@ (low confidence)"
                    )
                }
                return value
            }
            return localized(LocalizationKey.usageCollectingData, defaultValue: "Collecting data…")
        }
    }

    private var exhaustionText: String {
        switch stats?.message {
        case .atLimit:
            return localized(LocalizationKey.usageAtLimit, defaultValue: "At limit")
        case .resetPending:
            return localized(LocalizationKey.usageWaitingForReset, defaultValue: "Waiting for reset")
        case .resetsBeforeExhaustion:
            return localized(
                LocalizationKey.usageLikelyWontRunOut,
                defaultValue: "Likely won't run out before reset"
            )
        case .noExhaustionProjected:
            return localized(
                LocalizationKey.usageNotExpectedToRunOut,
                defaultValue: "Not expected to run out"
            )
        case .notEnoughData, nil:
            return localized(LocalizationKey.usageCollectingData, defaultValue: "Collecting data…")
        case .ready:
            if let date = stats?.exhaustionAt {
                return AppLocalization.dateTime(date, locale: locale)
            }
            return localized(LocalizationKey.usageCollectingData, defaultValue: "Collecting data…")
        }
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        AppLocalization.string(for: key, locale: locale, defaultValue: defaultValue)
    }

    private func signedDecimal(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return sign + AppLocalization.decimal(abs(value), fractionDigits: 1, locale: locale) + "%"
    }

    private func metric(_ titleKey: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(titleKey))
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
    }
}
