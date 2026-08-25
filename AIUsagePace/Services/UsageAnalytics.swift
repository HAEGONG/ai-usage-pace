import Foundation

enum UsageAnalytics {
    static let percentNoiseEpsilon = 0.05
    static let minimumSampleCount = 3
    static let minimumSpan: TimeInterval = 2 * 60 * 60
    static let paceWindow: TimeInterval = 24 * 60 * 60
    static let lowConfidenceGap: TimeInterval = 6 * 60 * 60

    static func stats(
        from snapshots: [UsageSnapshot],
        current: UsageSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> UsageStats {
        var pools: [UsagePoolID: PoolStats] = [:]
        for bucket in current.buckets {
            pools[bucket.id] = poolStats(
                for: bucket.id,
                snapshots: snapshots,
                current: current,
                now: now,
                calendar: calendar
            )
        }
        return UsageStats(pools: pools)
    }

    private static func poolStats(
        for pool: UsagePoolID,
        snapshots: [UsageSnapshot],
        current: UsageSnapshot,
        now: Date,
        calendar: Calendar
    ) -> PoolStats {
        let currentStart = cycleStart(current, pool: pool)
        let currentEnd = cycleEnd(current, pool: pool)
        let series = snapshots
            .filter { $0.accountFingerprint == current.accountFingerprint }
            .filter { cycleStart($0, pool: pool) == currentStart && cycleEnd($0, pool: pool) == currentEnd }
            .compactMap { snapshot -> (Date, Double)? in
                guard let percent = percentUsed(snapshot, pool: pool) else { return nil }
                return (snapshot.capturedAt, percent)
            }
            .sorted { $0.0 < $1.0 }

        let segment = currentSegment(series)
        let currentPercent = percentUsed(current, pool: pool) ?? segment.last?.1 ?? 0
        let today = todayDelta(segment: segment, now: now, calendar: calendar, currentPercent: currentPercent)

        guard let cycleEnd = currentEnd else {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: nil,
                exhaustionAt: nil,
                lowConfidence: false,
                message: .notEnoughData
            )
        }

        if cycleEnd <= now {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: nil,
                exhaustionAt: nil,
                lowConfidence: false,
                message: .resetPending
            )
        }

        let remainingPercent = max(0, 100 - currentPercent)
        if remainingPercent == 0 {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: nil,
                exhaustionAt: nil,
                lowConfidence: false,
                message: .atLimit
            )
        }

        let windowStart = now.addingTimeInterval(-paceWindow)
        let window = segment.filter { $0.0 >= windowStart }
        let span = (window.last?.0.timeIntervalSince(window.first?.0 ?? now)) ?? 0
        guard window.count >= minimumSampleCount, span >= minimumSpan else {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: nil,
                exhaustionAt: nil,
                lowConfidence: false,
                message: .notEnoughData
            )
        }

        let lowConfidence = hasLongGap(window)
        guard let actualRate = olsSlope(window) else {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: nil,
                exhaustionAt: nil,
                lowConfidence: lowConfidence,
                message: .notEnoughData
            )
        }

        if actualRate <= 0 {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: 0,
                exhaustionAt: nil,
                lowConfidence: lowConfidence,
                message: .ready
            )
        }

        let timeUntilReset = cycleEnd.timeIntervalSince(now)
        let idealRate = remainingPercent / timeUntilReset
        let paceRatio = idealRate > 0 ? actualRate / idealRate : nil
        let exhaustionAt = now.addingTimeInterval(remainingPercent / actualRate)
        let resetsBefore = exhaustionAt > cycleEnd

        return PoolStats(
            todayDelta: today.delta,
            todayIsSinceFirstRecord: today.sinceFirstRecord,
            paceRatio: paceRatio,
            exhaustionAt: resetsBefore ? nil : exhaustionAt,
            lowConfidence: lowConfidence,
            message: resetsBefore ? .resetsBeforeExhaustion : .ready
        )
    }

    static func currentSegment(_ series: [(Date, Double)]) -> [(Date, Double)] {
        guard var last = series.first else { return [] }
        var segment: [(Date, Double)] = [last]
        for sample in series.dropFirst() {
            let drop = last.1 - sample.1
            if drop > percentNoiseEpsilon {
                segment = [sample]
            } else {
                segment.append(sample)
            }
            last = sample
        }
        return segment
    }

    private static func todayDelta(
        segment: [(Date, Double)],
        now: Date,
        calendar: Calendar,
        currentPercent: Double
    ) -> (delta: Double?, sinceFirstRecord: Bool) {
        let midnight = calendar.startOfDay(for: now)
        let before = segment.last { $0.0 < midnight }
        let after = segment.first { $0.0 >= midnight }
        if let before, let after {
            let span = after.0.timeIntervalSince(before.0)
            guard span > 0 else {
                return (currentPercent - after.1, false)
            }
            let fraction = midnight.timeIntervalSince(before.0) / span
            let midnightPercent = before.1 + fraction * (after.1 - before.1)
            return (currentPercent - midnightPercent, false)
        }
        if let after {
            return (currentPercent - after.1, true)
        }
        return (nil, false)
    }

    private static func hasLongGap(_ samples: [(Date, Double)]) -> Bool {
        zip(samples, samples.dropFirst()).contains { earlier, later in
            later.0.timeIntervalSince(earlier.0) >= lowConfidenceGap
        }
    }

    private static func olsSlope(_ samples: [(Date, Double)]) -> Double? {
        let origin = samples[0].0
        let points = samples.map { ($0.0.timeIntervalSince(origin), $0.1) }
        let n = Double(points.count)
        let sumX = points.reduce(0.0) { $0 + $1.0 }
        let sumY = points.reduce(0.0) { $0 + $1.1 }
        let sumXY = points.reduce(0.0) { $0 + $1.0 * $1.1 }
        let sumXX = points.reduce(0.0) { $0 + $1.0 * $1.0 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }
        return (n * sumXY - sumX * sumY) / denominator
    }

    private static func percentUsed(_ snapshot: UsageSnapshot, pool: UsagePoolID) -> Double? {
        snapshot.buckets.first { $0.id == pool }?.percentUsed
    }

    private static func cycleStart(_ snapshot: UsageSnapshot, pool: UsagePoolID) -> Date? {
        snapshot.buckets.first { $0.id == pool }?.cycleStart(in: snapshot) ?? snapshot.cycleStart
    }

    private static func cycleEnd(_ snapshot: UsageSnapshot, pool: UsagePoolID) -> Date? {
        snapshot.buckets.first { $0.id == pool }?.cycleEnd(in: snapshot) ?? snapshot.cycleEnd
    }
}