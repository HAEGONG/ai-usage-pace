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
    @State private var isPaceHovered = false
    @State private var isPacePinned = false
    @State private var isExhaustionHovered = false
    @State private var isExhaustionPinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    if bucket.id == .grokWeekly {
                        ProviderIcon(providerID: "grok")
                    }
                    Text(LocalizedStringKey(bucket.id.titleLocalizationKey))
                }
                .font(.headline)
                Spacer()
                Text(verbatim: UsagePercentFormat.string(bucket.percentUsed, locale: locale))
                    .font(.headline)
                    .monospacedDigit()
            }
            ProgressView(value: bucket.progressFraction)
            metric(LocalizationKey.usageUsedToday, todayText)
            paceMetric
            exhaustionMetric
            if let cycleEnd = bucket.cycleEnd {
                metric(LocalizationKey.usageResets, AppLocalization.dateTime(cycleEnd, locale: locale))
            }
        }
    }

    private var todayText: String {
        guard let delta = stats?.todayDelta else {
            return localized(LocalizationKey.usageNoComparisonYet, defaultValue: "No comparison yet")
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
            return localized(LocalizationKey.usageNotEnoughHistory, defaultValue: "Not enough usage history")
        case .ready, .resetsBeforeExhaustion, .noExhaustionProjected:
            if let ratio = stats?.paceRatio {
                return AppLocalization.decimal(ratio, fractionDigits: 1, locale: locale) + "×"
            }
            return localized(LocalizationKey.usageNotEnoughHistory, defaultValue: "Not enough usage history")
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
            return localized(LocalizationKey.usageNotEnoughHistory, defaultValue: "Not enough usage history")
        case .ready:
            if let date = stats?.exhaustionAt {
                return AppLocalization.dateTime(date, locale: locale)
            }
            return localized(LocalizationKey.usageNotEnoughHistory, defaultValue: "Not enough usage history")
        }
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        AppLocalization.string(for: key, locale: locale, defaultValue: defaultValue)
    }

    private func signedDecimal(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return sign + AppLocalization.decimal(abs(value), fractionDigits: 1, locale: locale) + "%"
    }

    private var paceMetric: some View {
        HStack {
            Text(LocalizedStringKey(LocalizationKey.usagePace))
            Spacer()
            if paceDetailsAvailable {
                Button {
                    isExhaustionPinned = false
                    isPacePinned.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: paceText)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        isExhaustionPinned = false
                    }
                    isPaceHovered = isHovered
                }
                .accessibilityHint(Text(LocalizedStringKey(LocalizationKey.usagePaceDetailsAccessibilityHint)))
                .popover(isPresented: paceDetailsPresented, arrowEdge: .trailing) {
                    if let stats {
                        ForecastDetailsPopover(stats: stats, metric: .pace)
                            .environment(\.locale, locale)
                    }
                }
            } else {
                Text(verbatim: paceText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
    }

    private var paceDetailsAvailable: Bool {
        guard let stats else { return false }
        return stats.paceRatio != nil || stats.message == .notEnoughData
    }

    private var paceDetailsPresented: Binding<Bool> {
        Binding(
            get: { paceDetailsAvailable && (isPaceHovered || isPacePinned) },
            set: { isPresented in
                if !isPresented {
                    isPaceHovered = false
                    isPacePinned = false
                }
            }
        )
    }

    private var exhaustionMetric: some View {
        HStack {
            Text(LocalizedStringKey(LocalizationKey.usageRunsOut))
            Spacer()
            if exhaustionDetailsAvailable {
                Button {
                    isPacePinned = false
                    isExhaustionPinned.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: exhaustionText)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        isPacePinned = false
                    }
                    isExhaustionHovered = isHovered
                }
                .accessibilityHint(Text(LocalizedStringKey(LocalizationKey.usagePaceDetailsAccessibilityHint)))
                .popover(isPresented: exhaustionDetailsPresented, arrowEdge: .trailing) {
                    if let stats {
                        ForecastDetailsPopover(stats: stats, metric: .exhaustion)
                            .environment(\.locale, locale)
                    }
                }
            } else {
                Text(verbatim: exhaustionText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
    }

    private var exhaustionDetailsAvailable: Bool {
        guard let stats else { return false }
        switch stats.message {
        case .ready, .resetsBeforeExhaustion, .noExhaustionProjected, .notEnoughData:
            return true
        case .atLimit, .resetPending:
            return false
        }
    }

    private var exhaustionDetailsPresented: Binding<Bool> {
        Binding(
            get: {
                exhaustionDetailsAvailable && (isExhaustionHovered || isExhaustionPinned)
            },
            set: { isPresented in
                if !isPresented {
                    isExhaustionHovered = false
                    isExhaustionPinned = false
                }
            }
        )
    }

    private func metric(_ titleKey: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(titleKey))
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.body)
    }
}

private enum ForecastDetailsMetric: Equatable {
    case pace
    case exhaustion
}

private struct ForecastDetailsPopover: View {
    let stats: PoolStats
    let metric: ForecastDetailsMetric
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedStringKey(titleKey))
                    .font(.headline)
                Spacer()
                confidenceBadge
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(LocalizationKey.usagePaceDetailsCalculation))
                    .font(.subheadline.weight(.semibold))
                if metric == .exhaustion {
                    calculationStep(1, methodText)
                    calculationStep(2, exhaustionProjectionText)
                    calculationStep(3, formulaText)
                } else {
                    Text(verbatim: formulaText)
                        .font(.callout)
                    Text(verbatim: methodText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                detailRow(systemImage: "clock", text: observationText)
                if stats.paceDiagnostics.historicalCycleCount > 0 {
                    detailRow(systemImage: "calendar", text: historyCyclesText)
                }
                if let moreObservationText {
                    detailRow(systemImage: "hourglass", text: moreObservationText)
                }
                if stats.paceDiagnostics.usesCycleAverageFallback {
                    warningRow(
                        localized(
                            LocalizationKey.usagePaceDetailsProvisionalEstimate,
                            defaultValue: "Provisional estimate based on cycle-to-date average usage"
                        )
                    )
                }
                if stats.paceDiagnostics.hasAmbiguousUsageGap {
                    warningRow(
                        localized(
                            LocalizationKey.usagePaceDetailsAmbiguousGap,
                            defaultValue: "Includes a long interval with no observations"
                        )
                    )
                }
                if stats.paceDiagnostics.historyIsUnstable {
                    warningRow(
                        localized(
                            LocalizationKey.usagePaceDetailsUnstableHistory,
                            defaultValue: "Usage varies substantially between weekly cycles"
                        )
                    )
                }
            }

            Text(verbatim: definitionText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 310)
    }

    private var titleKey: String {
        switch metric {
        case .pace:
            LocalizationKey.usagePaceDetailsTitle
        case .exhaustion:
            LocalizationKey.usageRunsOutDetailsTitle
        }
    }

    private var formulaText: String {
        switch metric {
        case .pace:
            localized(
                LocalizationKey.usagePaceDetailsFormula,
                defaultValue: "Projected usage until reset ÷ remaining usage"
            )
        case .exhaustion:
            localized(
                LocalizationKey.usageRunsOutDetailsFormula,
                defaultValue: "Uses the first point where cumulative usage reaches the remaining allowance as the exhaustion time."
            )
        }
    }

    private var definitionText: String {
        switch metric {
        case .pace:
            localized(
                LocalizationKey.usagePaceDetailsDefinition,
                defaultValue: "1.0× means the remaining allowance is expected to run out around the reset time."
            )
        case .exhaustion:
            localized(
                LocalizationKey.usageRunsOutDetailsDefinition,
                defaultValue: "If projected usage does not reach the remaining allowance before reset, the app reports that exhaustion is unlikely."
            )
        }
    }

    private var exhaustionProjectionText: String {
        localized(
            LocalizationKey.usageRunsOutDetailsProjection,
            defaultValue: "Accumulates projected usage in 15-minute intervals until reset."
        )
    }

    private func calculationStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(verbatim: "\(number).")
                .foregroundStyle(.secondary)
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    private var confidenceBadge: some View {
        Text(verbatim: confidenceLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(confidenceColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(confidenceColor.opacity(0.12), in: Capsule())
    }

    private var confidenceLabel: String {
        localized(
            LocalizationKey.usagePaceDetailsConfidence,
            defaultValue: "Confidence"
        ) + ": " + confidenceText
    }

    private var confidenceText: String {
        switch stats.confidence {
        case .low:
            localized(LocalizationKey.usagePaceDetailsConfidenceLow, defaultValue: "Low")
        case .medium:
            localized(LocalizationKey.usagePaceDetailsConfidenceMedium, defaultValue: "Medium")
        case .high:
            localized(LocalizationKey.usagePaceDetailsConfidenceHigh, defaultValue: "High")
        }
    }

    private var confidenceColor: Color {
        switch stats.confidence {
        case .low: .orange
        case .medium: .blue
        case .high: .green
        }
    }

    private var methodText: String {
        switch stats.paceDiagnostics.cadence {
        case .monthly:
            localized(
                LocalizationKey.usagePaceDetailsMonthlyMethod,
                defaultValue: "Builds weekday and hourly rates from this cycle, smoothed with the overall average."
            )
        case .weekly:
            localized(
                LocalizationKey.usagePaceDetailsWeeklyMethod,
                defaultValue: "Builds weekday and hourly rates by blending this week with up to 8 recent cycles, weighting recent weeks more heavily."
            )
        }
    }

    private var observationText: String {
        AppLocalization.format(
            LocalizationKey.usagePaceDetailsObservation,
            locale: locale,
            arguments: [durationText(stats.paceDiagnostics.currentObservationDuration)],
            defaultValue: "%@ observed in the current cycle"
        )
    }

    private var historyCyclesText: String {
        AppLocalization.format(
            LocalizationKey.usagePaceDetailsHistoryCycles,
            locale: locale,
            arguments: [stats.paceDiagnostics.historicalCycleCount],
            defaultValue: "%d previous weekly cycles used"
        )
    }

    private var moreObservationText: String? {
        guard stats.paceDiagnostics.usesCycleAverageFallback,
              stats.paceDiagnostics.historicalCycleCount == 0
        else {
            return nil
        }
        let remaining = stats.paceDiagnostics.minimumObservationDuration
            - stats.paceDiagnostics.currentObservationDuration
        guard remaining > 0 else { return nil }
        return AppLocalization.format(
            LocalizationKey.usagePaceDetailsMoreObservation,
            locale: locale,
            arguments: [durationText(remaining, roundingUp: true)],
            defaultValue: "%@ more observation needed for a pattern-based estimate"
        )
    }

    private func detailRow(systemImage: String, text: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func warningRow(_ text: String) -> some View {
        detailRow(systemImage: "exclamationmark.triangle", text: text)
            .foregroundStyle(.orange)
    }

    private func durationText(_ duration: TimeInterval, roundingUp: Bool = false) -> String {
        let rawHours = max(0, duration / (60 * 60))
        let totalHours = roundingUp ? Int(ceil(rawHours)) : Int(floor(rawHours))
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return AppLocalization.format(
                LocalizationKey.usagePaceDetailsDurationDaysHours,
                locale: locale,
                arguments: [days, hours],
                defaultValue: "%1$d days %2$d hr"
            )
        }
        return AppLocalization.format(
            LocalizationKey.usagePaceDetailsDurationHours,
            locale: locale,
            arguments: [totalHours],
            defaultValue: "%d hr"
        )
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        AppLocalization.string(for: key, locale: locale, defaultValue: defaultValue)
    }
}

struct ProviderIcon: View {
    let providerID: String

    @ViewBuilder
    var body: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
    }

    private var assetName: String? {
        switch providerID {
        case "cursor":
            "CursorIcon"
        case "grok":
            "GrokIcon"
        case "codex":
            "CodexIcon"
        default:
            nil
        }
    }
}
