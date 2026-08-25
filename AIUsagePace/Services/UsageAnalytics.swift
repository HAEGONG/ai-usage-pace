import Foundation

enum UsageAnalytics {
    static let percentNoiseEpsilon = 0.05
    static let samplingInterval: TimeInterval = 15 * 60
    static let minimumCurrentSpan: TimeInterval = 24 * 60 * 60
    static let minimumWeeklyBlendSpan: TimeInterval = 2 * 60 * 60
    static let matureCurrentSpan: TimeInterval = 3 * 24 * 60 * 60
    static let ambiguousGap: TimeInterval = 6 * 60 * 60
    static let slotPriorDuration: TimeInterval = 4 * 60 * 60
    static let weeklyBlendHorizon: TimeInterval = 2 * 24 * 60 * 60
    static let maximumHistoricalWeeklyCycles = 8

    private enum Cadence {
        case monthly
        case weekly
    }

    private struct CycleKey: Hashable {
        let start: Date
        let end: Date
    }

    private struct Sample {
        let date: Date
        let percent: Double
        let cycle: CycleKey
    }

    private struct RateAccumulator {
        var usage = 0.0
        var duration = 0.0

        mutating func add(usage: Double, duration: TimeInterval, weight: Double) {
            self.usage += usage * weight
            self.duration += duration * weight
        }

        var rate: Double? {
            duration > 0 ? usage / duration : nil
        }
    }

    private struct RateProfile {
        let global: RateAccumulator
        let slots: [Int: RateAccumulator]
        let hasAmbiguousUsageGap: Bool

        var globalRate: Double? {
            global.rate
        }

        func expectedRate(at date: Date, calendar: Calendar) -> Double {
            guard let globalRate else { return 0 }
            let key = UsageAnalytics.slotKey(for: date, calendar: calendar)
            guard let slot = slots[key], let slotRate = slot.rate else {
                return globalRate
            }
            let slotWeight = slot.duration / (slot.duration + UsageAnalytics.slotPriorDuration)
            return slotRate * slotWeight + globalRate * (1 - slotWeight)
        }
    }

    private struct ForecastModel {
        let current: RateProfile?
        let historical: RateProfile?
        let currentWeight: Double
        let lowConfidence: Bool

        func expectedRate(at date: Date, calendar: Calendar) -> Double {
            switch (current, historical) {
            case let (.some(current), .some(historical)):
                return current.expectedRate(at: date, calendar: calendar) * currentWeight
                    + historical.expectedRate(at: date, calendar: calendar) * (1 - currentWeight)
            case let (.some(current), nil):
                return current.expectedRate(at: date, calendar: calendar)
            case let (nil, .some(historical)):
                return historical.expectedRate(at: date, calendar: calendar)
            case (nil, nil):
                return 0
            }
        }
    }

    private struct Projection {
        let usageUntilReset: Double
        let exhaustionAt: Date?
    }

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
        let allSamples = samples(for: pool, snapshots: snapshots, current: current, now: now)
        let currentStart = cycleStart(current, pool: pool)
        let currentEnd = cycleEnd(current, pool: pool)
        let currentSeries: [(Date, Double)]
        if let currentStart, let currentEnd {
            currentSeries = allSamples
                .filter { $0.cycle.start == currentStart && $0.cycle.end == currentEnd }
                .map { ($0.date, $0.percent) }
        } else {
            currentSeries = []
        }
        let segment = currentSegment(currentSeries)
        let currentPercent = percentUsed(current, pool: pool) ?? segment.last?.1 ?? 0
        let today = todayDelta(segment: segment, now: now, calendar: calendar, currentPercent: currentPercent)

        guard let currentStart, let cycleEnd = currentEnd else {
            return unavailableStats(today: today, message: .notEnoughData)
        }

        if cycleEnd <= now {
            return unavailableStats(today: today, message: .resetPending)
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

        guard let model = forecastModel(
            cadence: cadence(for: pool),
            allSamples: allSamples,
            currentCycle: CycleKey(start: currentStart, end: cycleEnd),
            currentSegment: segment,
            now: now,
            calendar: calendar
        ) else {
            return unavailableStats(today: today, message: .notEnoughData)
        }

        let projection = project(
            model: model,
            remainingPercent: remainingPercent,
            now: now,
            cycleEnd: cycleEnd,
            calendar: calendar
        )
        let paceRatio = projection.usageUntilReset / remainingPercent

        if projection.usageUntilReset <= percentNoiseEpsilon {
            return PoolStats(
                todayDelta: today.delta,
                todayIsSinceFirstRecord: today.sinceFirstRecord,
                paceRatio: 0,
                exhaustionAt: nil,
                lowConfidence: model.lowConfidence,
                message: .noExhaustionProjected
            )
        }

        return PoolStats(
            todayDelta: today.delta,
            todayIsSinceFirstRecord: today.sinceFirstRecord,
            paceRatio: paceRatio,
            exhaustionAt: projection.exhaustionAt,
            lowConfidence: model.lowConfidence,
            message: projection.exhaustionAt == nil ? .resetsBeforeExhaustion : .ready
        )
    }

    private static func unavailableStats(
        today: (delta: Double?, sinceFirstRecord: Bool),
        message: PoolMessage
    ) -> PoolStats {
        PoolStats(
            todayDelta: today.delta,
            todayIsSinceFirstRecord: today.sinceFirstRecord,
            paceRatio: nil,
            exhaustionAt: nil,
            lowConfidence: false,
            message: message
        )
    }

    private static func forecastModel(
        cadence: Cadence,
        allSamples: [Sample],
        currentCycle: CycleKey,
        currentSegment: [(Date, Double)],
        now: Date,
        calendar: Calendar
    ) -> ForecastModel? {
        let currentSpan = seriesSpan(currentSegment)
        let currentProfile = makeProfile(series: currentSegment, calendar: calendar)

        switch cadence {
        case .monthly:
            guard currentSpan >= minimumCurrentSpan, let currentProfile else { return nil }
            return ForecastModel(
                current: currentProfile,
                historical: nil,
                currentWeight: 1,
                lowConfidence: currentSpan < matureCurrentSpan || currentProfile.hasAmbiguousUsageGap
            )

        case .weekly:
            let historical = historicalWeeklyProfiles(
                from: allSamples,
                excluding: currentCycle,
                now: now,
                calendar: calendar
            )
            let usableCurrent = currentSpan >= minimumWeeklyBlendSpan ? currentProfile : nil

            if let historicalProfile = historical.profile {
                let weight = usableCurrent == nil ? 0 : currentSpan / (currentSpan + weeklyBlendHorizon)
                let lowConfidence = historical.cycleRates.count < 3
                    || historicalProfile.hasAmbiguousUsageGap
                    || ratesAreUnstable(historical.cycleRates)
                return ForecastModel(
                    current: usableCurrent,
                    historical: historicalProfile,
                    currentWeight: weight,
                    lowConfidence: lowConfidence
                )
            }

            guard currentSpan >= minimumCurrentSpan, let currentProfile else { return nil }
            return ForecastModel(
                current: currentProfile,
                historical: nil,
                currentWeight: 1,
                lowConfidence: currentSpan < matureCurrentSpan || currentProfile.hasAmbiguousUsageGap
            )
        }
    }

    private static func historicalWeeklyProfiles(
        from samples: [Sample],
        excluding currentCycle: CycleKey,
        now: Date,
        calendar: Calendar
    ) -> (profile: RateProfile?, cycleRates: [Double]) {
        let grouped = Dictionary(grouping: samples.filter {
            $0.cycle != currentCycle && $0.cycle.end <= now
        }, by: \.cycle)
        let cycles = grouped.keys.sorted { $0.end > $1.end }.prefix(maximumHistoricalWeeklyCycles)

        var weightedSeries: [([(Date, Double)], Double)] = []
        var cycleRates: [Double] = []
        for (index, cycle) in cycles.enumerated() {
            let series = currentSegment(
                (grouped[cycle] ?? [])
                    .sorted { $0.date < $1.date }
                    .map { ($0.date, $0.percent) }
            )
            guard seriesSpan(series) >= minimumCurrentSpan,
                  let profile = makeProfile(series: series, calendar: calendar),
                  let rate = profile.globalRate
            else {
                continue
            }
            cycleRates.append(rate)
            weightedSeries.append((series, pow(0.8, Double(index))))
        }

        return (
            makeProfile(weightedSeries: weightedSeries, calendar: calendar),
            cycleRates
        )
    }

    private static func makeProfile(
        series: [(Date, Double)],
        calendar: Calendar
    ) -> RateProfile? {
        makeProfile(weightedSeries: [(series, 1)], calendar: calendar)
    }

    private static func makeProfile(
        weightedSeries: [([(Date, Double)], Double)],
        calendar: Calendar
    ) -> RateProfile? {
        var global = RateAccumulator()
        var slots: [Int: RateAccumulator] = [:]
        var hasAmbiguousUsageGap = false

        for (rawSeries, weight) in weightedSeries {
            let series = monotonic(rawSeries)
            guard series.count >= 2 else { continue }

            for (earlier, later) in zip(series, series.dropFirst()) {
                let duration = later.0.timeIntervalSince(earlier.0)
                guard duration > 0 else { continue }
                let usage = max(0, later.1 - earlier.1)
                // Weight by elapsed time, not by refresh count. Dense manual
                // refreshes therefore produce the same rate as regular samples.
                global.add(usage: usage, duration: duration, weight: weight)

                let ambiguous = duration >= ambiguousGap && usage > percentNoiseEpsilon
                if ambiguous {
                    // Keep the delta in the overall rate, but do not guess which
                    // hour inside a long unobserved gap should own the usage.
                    hasAmbiguousUsageGap = true
                    continue
                }

                let rate = usage / duration
                var intervalStart = earlier.0
                while intervalStart < later.0 {
                    let intervalEnd = min(later.0, nextSamplingBoundary(after: intervalStart))
                    let intervalDuration = intervalEnd.timeIntervalSince(intervalStart)
                    let midpoint = intervalStart.addingTimeInterval(intervalDuration / 2)
                    let key = slotKey(for: midpoint, calendar: calendar)
                    var accumulator = slots[key] ?? RateAccumulator()
                    accumulator.add(
                        usage: rate * intervalDuration,
                        duration: intervalDuration,
                        weight: weight
                    )
                    slots[key] = accumulator
                    intervalStart = intervalEnd
                }
            }
        }

        guard global.duration > 0 else { return nil }
        return RateProfile(
            global: global,
            slots: slots,
            hasAmbiguousUsageGap: hasAmbiguousUsageGap
        )
    }

    private static func project(
        model: ForecastModel,
        remainingPercent: Double,
        now: Date,
        cycleEnd: Date,
        calendar: Calendar
    ) -> Projection {
        var projectedUsage = 0.0
        var exhaustionAt: Date?
        var intervalStart = now

        while intervalStart < cycleEnd {
            let intervalEnd = min(cycleEnd, nextSamplingBoundary(after: intervalStart))
            let duration = intervalEnd.timeIntervalSince(intervalStart)
            let midpoint = intervalStart.addingTimeInterval(duration / 2)
            let rate = max(0, model.expectedRate(at: midpoint, calendar: calendar))
            let intervalUsage = rate * duration

            if exhaustionAt == nil,
               rate > 0,
               projectedUsage + intervalUsage >= remainingPercent {
                let needed = remainingPercent - projectedUsage
                exhaustionAt = intervalStart.addingTimeInterval(needed / rate)
            }

            projectedUsage += intervalUsage
            intervalStart = intervalEnd
        }

        if exhaustionAt == nil, remainingPercent - projectedUsage <= percentNoiseEpsilon {
            exhaustionAt = cycleEnd
        }

        return Projection(usageUntilReset: projectedUsage, exhaustionAt: exhaustionAt)
    }

    static func currentSegment(_ series: [(Date, Double)]) -> [(Date, Double)] {
        let sorted = series.sorted { $0.0 < $1.0 }
        guard var last = sorted.first else { return [] }
        var segment: [(Date, Double)] = [last]
        for sample in sorted.dropFirst() {
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

    private static func monotonic(_ series: [(Date, Double)]) -> [(Date, Double)] {
        var maximum = -Double.infinity
        return series.map { date, percent in
            maximum = max(maximum, percent)
            return (date, maximum)
        }
    }

    private static func samples(
        for pool: UsagePoolID,
        snapshots: [UsageSnapshot],
        current: UsageSnapshot,
        now: Date
    ) -> [Sample] {
        snapshots
            .filter { $0.accountFingerprint == current.accountFingerprint && $0.capturedAt <= now }
            .compactMap { snapshot -> Sample? in
                guard let percent = percentUsed(snapshot, pool: pool),
                      let start = cycleStart(snapshot, pool: pool),
                      let end = cycleEnd(snapshot, pool: pool)
                else {
                    return nil
                }
                return Sample(
                    date: snapshot.capturedAt,
                    percent: percent,
                    cycle: CycleKey(start: start, end: end)
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func cadence(for pool: UsagePoolID) -> Cadence {
        switch pool {
        case .cursorModels, .otherModels:
            return .monthly
        case .grokBotWeekly, .grokWeekly:
            return .weekly
        }
    }

    private static func ratesAreUnstable(_ rates: [Double]) -> Bool {
        guard rates.count >= 2 else { return true }
        let mean = rates.reduce(0, +) / Double(rates.count)
        guard mean > 0 else { return false }
        let variance = rates.reduce(0) { partial, rate in
            partial + pow(rate - mean, 2)
        } / Double(rates.count)
        return sqrt(variance) / mean > 0.5
    }

    private static func seriesSpan(_ series: [(Date, Double)]) -> TimeInterval {
        guard let first = series.first?.0, let last = series.last?.0 else { return 0 }
        return max(0, last.timeIntervalSince(first))
    }

    private static func nextSamplingBoundary(after date: Date) -> Date {
        let timestamp = date.timeIntervalSinceReferenceDate
        let next = (floor(timestamp / samplingInterval) + 1) * samplingInterval
        return Date(timeIntervalSinceReferenceDate: next)
    }

    private static func slotKey(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date) - 1
        let hour = calendar.component(.hour, from: date)
        return weekday * 24 + hour
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
