import SwiftUI

struct ProviderUsageView: View {
    let snapshot: UsageSnapshot
    var stats: UsageStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(snapshot.buckets, id: \.id) { bucket in
                PoolUsageRow(bucket: bucket, stats: stats?.pools[bucket.id])
            }

            if let cycleEnd = snapshot.cycleEnd {
                labeledRow("Reset", value: cycleEnd.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func labeledRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

private struct PoolUsageRow: View {
    let bucket: UsageBucket
    var stats: PoolStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bucket.id.title)
                    .font(.headline)
                Spacer()
                Text(UsagePercentFormat.string(bucket.percentUsed))
                    .font(.headline)
                    .monospacedDigit()
            }
            ProgressView(value: bucket.progressFraction)
            metric("Today", todayText)
            metric("Pace", paceText)
            metric("Exhaustion", exhaustionText)
        }
    }

    private var todayText: String {
        guard let delta = stats?.todayDelta else {
            return "Not enough data"
        }
        let value = String(format: "%+.1f%%", delta)
        if stats?.todayIsSinceFirstRecord == true {
            return "\(value) since first record today"
        }
        return value
    }

    private var paceText: String {
        switch stats?.message {
        case .atLimit:
            return "At limit"
        case .resetPending:
            return "Reset pending"
        case .notEnoughData, nil:
            return "Not enough data"
        case .ready, .resetsBeforeExhaustion:
            if let ratio = stats?.paceRatio {
                let text = String(format: "%.1f×", ratio)
                return stats?.lowConfidence == true ? "\(text) (low confidence)" : text
            }
            return "Not enough data"
        }
    }

    private var exhaustionText: String {
        switch stats?.message {
        case .atLimit:
            return "At limit"
        case .resetPending:
            return "Reset pending"
        case .resetsBeforeExhaustion:
            return "Will likely reset before exhaustion"
        case .notEnoughData, nil:
            return "Not enough data"
        case .ready:
            if let date = stats?.exhaustionAt {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
            return "Not enough data"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}