import XCTest
@testable import AIUsagePace

final class UsageAnalyticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_777_046_400)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testMonthlyPoolCollectsDataForFirstDay() {
        let cycleStart = now.addingTimeInterval(-24 * 60 * 60)
        let cycleEnd = cycleStart.addingTimeInterval(30 * 24 * 60 * 60)
        let samples = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 60 * 60),
            observedEnd: now,
            startPercent: 1,
            ratePerDay: 12
        )

        let stats = UsageAnalytics.stats(
            from: samples,
            current: samples.last!,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(stats.pools[.cursorModels]?.message, .notEnoughData)
        XCTAssertNil(stats.pools[.cursorModels]?.exhaustionAt)
        XCTAssertNil(stats.pools[.cursorModels]?.paceRatio)
    }

    func testMonthlyLinearRateAndExhaustionAfterMatureObservation() {
        let cycleStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(5 * 24 * 60 * 60)
        let samples = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 24 * 60 * 60),
            observedEnd: now,
            startPercent: 10,
            ratePerDay: 10
        )

        let stats = UsageAnalytics.stats(
            from: samples,
            current: samples.last!,
            now: now,
            calendar: calendar
        )
        let pool = stats.pools[.cursorModels]

        XCTAssertEqual(pool?.message, .ready)
        XCTAssertEqual(pool?.paceRatio ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(pool?.exhaustionAt?.timeIntervalSince(now) ?? 0, 5 * 24 * 60 * 60, accuracy: 1)
        XCTAssertEqual(pool?.lowConfidence, false)
    }

    func testMonthlyFastRateKeepsPaceAboveOneAfterFindingExhaustion() {
        let cycleStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(10 * 24 * 60 * 60)
        let samples = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 24 * 60 * 60),
            observedEnd: now,
            startPercent: 60,
            ratePerDay: 5
        )

        let pool = UsageAnalytics.stats(
            from: samples,
            current: samples.last!,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.message, .ready)
        XCTAssertEqual(pool?.paceRatio ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(pool?.exhaustionAt?.timeIntervalSince(now) ?? 0, 4 * 24 * 60 * 60, accuracy: 1)
    }

    func testDenseRefreshesDoNotChangeMonthlyForecast() {
        let cycleStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(10 * 24 * 60 * 60)
        let regular = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 24 * 60 * 60),
            observedEnd: now,
            startPercent: 20,
            ratePerDay: 5,
            interval: 60 * 60
        )
        let dense = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 24 * 60 * 60),
            observedEnd: now,
            startPercent: 20,
            ratePerDay: 5,
            interval: 5 * 60
        )

        let regularStats = UsageAnalytics.stats(
            from: regular,
            current: regular.last!,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]
        let denseStats = UsageAnalytics.stats(
            from: dense,
            current: dense.last!,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(regularStats?.paceRatio ?? 0, denseStats?.paceRatio ?? 0, accuracy: 0.0001)
        XCTAssertEqual(
            regularStats?.exhaustionAt?.timeIntervalSince1970 ?? 0,
            denseStats?.exhaustionAt?.timeIntervalSince1970 ?? 0,
            accuracy: 1
        )
    }

    func testFlatMonthlyUsageHasNoExhaustionProjected() {
        let cycleStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(10 * 24 * 60 * 60)
        let samples = usageSeries(
            pool: .otherModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 24 * 60 * 60),
            observedEnd: now,
            startPercent: 40,
            ratePerDay: 0
        )

        let pool = UsageAnalytics.stats(
            from: samples,
            current: samples.last!,
            now: now,
            calendar: calendar
        ).pools[.otherModels]

        XCTAssertEqual(pool?.message, .noExhaustionProjected)
        XCTAssertEqual(pool?.paceRatio, 0)
        XCTAssertNil(pool?.exhaustionAt)
    }

    func testAtLimitDoesNotRequireHistory() {
        let cycleStart = now.addingTimeInterval(-24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(29 * 24 * 60 * 60)
        let current = snapshot(
            at: now,
            pool: .cursorModels,
            percent: 100,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd
        )

        let pool = UsageAnalytics.stats(
            from: [current],
            current: current,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.message, .atLimit)
        XCTAssertNil(pool?.exhaustionAt)
    }

    func testResetPendingDoesNotRequireHistory() {
        let current = snapshot(
            at: now,
            pool: .cursorModels,
            percent: 40,
            cycleStart: now.addingTimeInterval(-30 * 24 * 60 * 60),
            cycleEnd: now.addingTimeInterval(-60)
        )

        let pool = UsageAnalytics.stats(
            from: [current],
            current: current,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.message, .resetPending)
    }

    func testPercentDropStartsNewSegment() {
        let series: [(Date, Double)] = [
            (now.addingTimeInterval(-4 * 60 * 60), 80),
            (now.addingTimeInterval(-3 * 60 * 60), 90),
            (now.addingTimeInterval(-2 * 60 * 60), 10),
            (now.addingTimeInterval(-1 * 60 * 60), 11),
            (now, 12),
        ]

        let segment = UsageAnalytics.currentSegment(series)

        XCTAssertEqual(segment.count, 3)
        XCTAssertEqual(segment.first?.1, 10)
    }

    func testTinyDropIsTreatedAsNoise() {
        let series: [(Date, Double)] = [
            (now.addingTimeInterval(-3 * 60 * 60), 10),
            (now.addingTimeInterval(-2 * 60 * 60), 9.97),
            (now.addingTimeInterval(-1 * 60 * 60), 11),
        ]

        XCTAssertEqual(UsageAnalytics.currentSegment(series).count, 3)
    }

    func testAmbiguousLongGapMarksMonthlyForecastLowConfidence() {
        let cycleStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(10 * 24 * 60 * 60)
        let observedStart = now.addingTimeInterval(-4 * 24 * 60 * 60)
        let full = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: observedStart,
            observedEnd: now,
            startPercent: 10,
            ratePerDay: 5
        )
        let gapStart = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let gapEnd = gapStart.addingTimeInterval(8 * 60 * 60)
        let withGap = full.filter { snapshot in
            snapshot.capturedAt <= gapStart || snapshot.capturedAt >= gapEnd
        }

        let pool = UsageAnalytics.stats(
            from: withGap,
            current: withGap.last!,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.message, .resetsBeforeExhaustion)
        XCTAssertEqual(pool?.lowConfidence, true)
    }

    func testTodayInterpolatesAcrossLocalMidnight() {
        let midnight = calendar.startOfDay(for: now)
        let currentTime = midnight.addingTimeInterval(12 * 60 * 60)
        let cycleStart = midnight.addingTimeInterval(-5 * 24 * 60 * 60)
        let cycleEnd = midnight.addingTimeInterval(25 * 24 * 60 * 60)
        let samples = [
            snapshot(
                at: midnight.addingTimeInterval(-2 * 60 * 60),
                pool: .cursorModels,
                percent: 10,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            ),
            snapshot(
                at: midnight.addingTimeInterval(2 * 60 * 60),
                pool: .cursorModels,
                percent: 14,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            ),
            snapshot(
                at: currentTime,
                pool: .cursorModels,
                percent: 20,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            ),
        ]

        let pool = UsageAnalytics.stats(
            from: samples,
            current: samples[2],
            now: currentTime,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.todayDelta ?? 0, 8, accuracy: 0.0001)
        XCTAssertEqual(pool?.todayIsSinceFirstRecord, false)
    }

    func testTodayFallsBackToFirstRecordLabel() {
        let midnight = calendar.startOfDay(for: now)
        let currentTime = midnight.addingTimeInterval(6 * 60 * 60)
        let cycleStart = midnight.addingTimeInterval(-5 * 24 * 60 * 60)
        let cycleEnd = midnight.addingTimeInterval(25 * 24 * 60 * 60)
        let samples = [
            snapshot(
                at: midnight.addingTimeInterval(60 * 60),
                pool: .cursorModels,
                percent: 5,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            ),
            snapshot(
                at: currentTime,
                pool: .cursorModels,
                percent: 8,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            ),
        ]

        let pool = UsageAnalytics.stats(
            from: samples,
            current: samples[1],
            now: currentTime,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.todayDelta, 3)
        XCTAssertEqual(pool?.todayIsSinceFirstRecord, true)
    }

    func testMonthlyExhaustionAfterResetIsFlagged() {
        let cycleStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let cycleEnd = now.addingTimeInterval(2 * 24 * 60 * 60)
        let samples = usageSeries(
            pool: .cursorModels,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: now.addingTimeInterval(-4 * 24 * 60 * 60),
            observedEnd: now,
            startPercent: 36,
            ratePerDay: 1
        )

        let pool = UsageAnalytics.stats(
            from: samples,
            current: samples.last!,
            now: now,
            calendar: calendar
        ).pools[.cursorModels]

        XCTAssertEqual(pool?.message, .resetsBeforeExhaustion)
        XCTAssertEqual(pool?.paceRatio ?? 0, 2 / 60, accuracy: 0.0001)
        XCTAssertNil(pool?.exhaustionAt)
    }

    func testWeeklyPoolsReuseThreeStablePreviousCyclesImmediatelyAfterReset() {
        for poolID in [UsagePoolID.grokBotWeekly, .grokWeekly] {
            let currentStart = now.addingTimeInterval(-60 * 60)
            let currentEnd = currentStart.addingTimeInterval(7 * 24 * 60 * 60)
            var samples = previousWeeklyCycles(
                pool: poolID,
                count: 3,
                before: currentStart,
                ratePerDay: 10
            )
            let current = snapshot(
                at: now,
                pool: poolID,
                percent: 1,
                cycleStart: currentStart,
                cycleEnd: currentEnd
            )
            samples.append(current)

            let stats = UsageAnalytics.stats(
                from: samples,
                current: current,
                now: now,
                calendar: calendar
            ).pools[poolID]

            XCTAssertEqual(stats?.message, .resetsBeforeExhaustion)
            XCTAssertEqual(stats?.paceRatio ?? 0, (10 * (167.0 / 24)) / 99, accuracy: 0.005)
            XCTAssertEqual(stats?.lowConfidence, false)
        }
    }

    func testSinglePreviousWeeklyCycleIsUsableButLowConfidence() {
        let currentStart = now.addingTimeInterval(-60 * 60)
        let currentEnd = currentStart.addingTimeInterval(7 * 24 * 60 * 60)
        var samples = previousWeeklyCycles(
            pool: .grokBotWeekly,
            count: 1,
            before: currentStart,
            ratePerDay: 10
        )
        let current = snapshot(
            at: now,
            pool: .grokBotWeekly,
            percent: 1,
            cycleStart: currentStart,
            cycleEnd: currentEnd
        )
        samples.append(current)

        let pool = UsageAnalytics.stats(
            from: samples,
            current: current,
            now: now,
            calendar: calendar
        ).pools[.grokBotWeekly]

        XCTAssertNotEqual(pool?.message, .notEnoughData)
        XCTAssertEqual(pool?.lowConfidence, true)
    }

    func testFirstWeeklyCycleAlsoRequiresOneDayOfCurrentData() {
        let cycleStart = now.addingTimeInterval(-4 * 60 * 60)
        let cycleEnd = cycleStart.addingTimeInterval(7 * 24 * 60 * 60)
        let samples = usageSeries(
            pool: .grokWeekly,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            observedStart: cycleStart,
            observedEnd: now,
            startPercent: 0,
            ratePerDay: 12
        )

        let pool = UsageAnalytics.stats(
            from: samples,
            current: samples.last!,
            now: now,
            calendar: calendar
        ).pools[.grokWeekly]

        XCTAssertEqual(pool?.message, .notEnoughData)
    }

    func testWeeklyForecastBlendsCurrentAndHistoricalRates() {
        let currentStart = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let currentEnd = now.addingTimeInterval(5 * 24 * 60 * 60)
        var samples = previousWeeklyCycles(
            pool: .grokBotWeekly,
            count: 3,
            before: currentStart,
            ratePerDay: 2
        )
        let currentSeries = usageSeries(
            pool: .grokBotWeekly,
            cycleStart: currentStart,
            cycleEnd: currentEnd,
            observedStart: currentStart,
            observedEnd: now,
            startPercent: 0,
            ratePerDay: 10
        )
        samples.append(contentsOf: currentSeries)

        let pool = UsageAnalytics.stats(
            from: samples,
            current: currentSeries.last!,
            now: now,
            calendar: calendar
        ).pools[.grokBotWeekly]

        XCTAssertEqual(pool?.message, .resetsBeforeExhaustion)
        XCTAssertEqual(pool?.paceRatio ?? 0, 30 / 80, accuracy: 0.005)
        XCTAssertEqual(pool?.lowConfidence, false)
    }

    func testWeeklyHistoryLearnsThatAnObservedWeekendIsIdle() {
        let currentStart = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: 4,
            hour: 0
        ))!
        let currentNow = currentStart.addingTimeInterval(6 * 24 * 60 * 60)
        let currentEnd = currentStart.addingTimeInterval(7 * 24 * 60 * 60)
        let current = snapshot(
            at: currentNow,
            pool: .grokBotWeekly,
            percent: 90,
            cycleStart: currentStart,
            cycleEnd: currentEnd
        )

        var patternedRecords = patternedWeeklyCycles(count: 3, before: currentStart)
        patternedRecords.append(current)
        var uniformRecords = previousWeeklyCycles(
            pool: .grokBotWeekly,
            count: 3,
            before: currentStart,
            ratePerDay: 40.0 / 7
        )
        uniformRecords.append(current)

        let patterned = UsageAnalytics.stats(
            from: patternedRecords,
            current: current,
            now: currentNow,
            calendar: calendar
        ).pools[.grokBotWeekly]
        let uniform = UsageAnalytics.stats(
            from: uniformRecords,
            current: current,
            now: currentNow,
            calendar: calendar
        ).pools[.grokBotWeekly]

        XCTAssertEqual(patterned?.message, .resetsBeforeExhaustion)
        XCTAssertEqual(uniform?.message, .resetsBeforeExhaustion)
        XCTAssertLessThan(patterned?.paceRatio ?? 1, (uniform?.paceRatio ?? 0) * 0.8)
    }

    func testMonthlyAndWeeklyPoolsUseIndependentCadenceRules() {
        let monthlyStart = now.addingTimeInterval(-24 * 60 * 60)
        let monthlyEnd = monthlyStart.addingTimeInterval(30 * 24 * 60 * 60)
        let weeklyStart = now.addingTimeInterval(-60 * 60)
        let weeklyEnd = weeklyStart.addingTimeInterval(7 * 24 * 60 * 60)
        var records = previousWeeklyCycles(
            pool: .grokBotWeekly,
            count: 3,
            before: weeklyStart,
            ratePerDay: 10
        )
        records.append(
            mixedSnapshot(
                at: now,
                cursorPercent: 2,
                grokBotPercent: 1,
                monthlyStart: monthlyStart,
                monthlyEnd: monthlyEnd,
                weeklyStart: weeklyStart,
                weeklyEnd: weeklyEnd
            )
        )

        let current = records.last!
        let stats = UsageAnalytics.stats(
            from: records,
            current: current,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(stats.pools[.cursorModels]?.message, .notEnoughData)
        XCTAssertNotEqual(stats.pools[.grokBotWeekly]?.message, .notEnoughData)
    }

    private func usageSeries(
        pool: UsagePoolID,
        cycleStart: Date,
        cycleEnd: Date,
        observedStart: Date,
        observedEnd: Date,
        startPercent: Double,
        ratePerDay: Double,
        interval: TimeInterval = 60 * 60
    ) -> [UsageSnapshot] {
        var result: [UsageSnapshot] = []
        var date = observedStart
        while date < observedEnd {
            let elapsedDays = date.timeIntervalSince(observedStart) / (24 * 60 * 60)
            result.append(
                snapshot(
                    at: date,
                    pool: pool,
                    percent: startPercent + ratePerDay * elapsedDays,
                    cycleStart: cycleStart,
                    cycleEnd: cycleEnd
                )
            )
            date = date.addingTimeInterval(interval)
        }
        let elapsedDays = observedEnd.timeIntervalSince(observedStart) / (24 * 60 * 60)
        result.append(
            snapshot(
                at: observedEnd,
                pool: pool,
                percent: startPercent + ratePerDay * elapsedDays,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            )
        )
        return result
    }

    private func previousWeeklyCycles(
        pool: UsagePoolID,
        count: Int,
        before currentStart: Date,
        ratePerDay: Double
    ) -> [UsageSnapshot] {
        var result: [UsageSnapshot] = []
        let cycleDuration = 7 * 24 * 60 * 60.0
        for offset in 0..<count {
            let cycleEnd = currentStart.addingTimeInterval(-Double(offset) * cycleDuration)
            let cycleStart = cycleEnd.addingTimeInterval(-cycleDuration)
            result.append(contentsOf: usageSeries(
                pool: pool,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd,
                observedStart: cycleStart,
                observedEnd: cycleEnd,
                startPercent: 0,
                ratePerDay: ratePerDay
            ))
        }
        return result
    }

    private func patternedWeeklyCycles(
        count: Int,
        before currentStart: Date
    ) -> [UsageSnapshot] {
        var result: [UsageSnapshot] = []
        let cycleDuration = 7 * 24 * 60 * 60.0
        for offset in 0..<count {
            let cycleEnd = currentStart.addingTimeInterval(-Double(offset) * cycleDuration)
            let cycleStart = cycleEnd.addingTimeInterval(-cycleDuration)
            var date = cycleStart
            var percent = 0.0
            result.append(snapshot(
                at: date,
                pool: .grokBotWeekly,
                percent: percent,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd
            ))

            while date < cycleEnd {
                let midpoint = date.addingTimeInterval(30 * 60)
                let weekday = calendar.component(.weekday, from: midpoint)
                let hour = calendar.component(.hour, from: midpoint)
                if (2...6).contains(weekday), (9..<17).contains(hour) {
                    percent += 1
                }
                date = date.addingTimeInterval(60 * 60)
                result.append(snapshot(
                    at: date,
                    pool: .grokBotWeekly,
                    percent: percent,
                    cycleStart: cycleStart,
                    cycleEnd: cycleEnd
                ))
            }
        }
        return result
    }

    private func snapshot(
        at date: Date,
        pool: UsagePoolID,
        percent: Double,
        cycleStart: Date,
        cycleEnd: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: pool == .grokWeekly ? "grok" : "cursor",
            accountFingerprint: "aaa",
            capturedAt: date,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            buckets: [
                UsageBucket(
                    id: pool,
                    meter: .metered(percentUsed: percent, absolute: nil),
                    cycleStart: cycleStart,
                    cycleEnd: cycleEnd
                ),
            ],
            membershipType: "pro_plus",
            limitType: "user",
            totalPercentUsed: nil
        )
    }

    private func mixedSnapshot(
        at date: Date,
        cursorPercent: Double,
        grokBotPercent: Double,
        monthlyStart: Date,
        monthlyEnd: Date,
        weeklyStart: Date,
        weeklyEnd: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: "cursor",
            accountFingerprint: "aaa",
            capturedAt: date,
            cycleStart: monthlyStart,
            cycleEnd: monthlyEnd,
            buckets: [
                UsageBucket(
                    id: .cursorModels,
                    meter: .metered(percentUsed: cursorPercent, absolute: nil),
                    cycleStart: monthlyStart,
                    cycleEnd: monthlyEnd
                ),
                UsageBucket(
                    id: .grokBotWeekly,
                    meter: .metered(percentUsed: grokBotPercent, absolute: nil),
                    cycleStart: weeklyStart,
                    cycleEnd: weeklyEnd
                ),
            ],
            membershipType: "pro_plus",
            limitType: "user",
            totalPercentUsed: nil
        )
    }
}
