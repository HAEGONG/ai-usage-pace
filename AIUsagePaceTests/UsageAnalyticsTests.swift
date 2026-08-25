import XCTest
@testable import AIUsagePace

final class UsageAnalyticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_777_046_400) // 2026-05-05 00:00 UTC + 12h later we'll set
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNotEnoughSamples() {
        let current = snapshot(at: now, percent: 10)
        let stats = UsageAnalytics.stats(
            from: [snapshot(at: now.addingTimeInterval(-3600), percent: 8), current],
            current: current,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .notEnoughData)
    }

    func testSpanUnderTwoHoursIsNotEnoughData() {
        let samples = [
            snapshot(at: now.addingTimeInterval(-5400), percent: 8),
            snapshot(at: now.addingTimeInterval(-3600), percent: 9),
            snapshot(at: now, percent: 10),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[2], now: now, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .notEnoughData)
    }

    func testLinearPaceAndExhaustion() {
        let cycleEnd = now.addingTimeInterval(10 * 3600)
        let samples = [
            snapshot(at: now.addingTimeInterval(-3 * 3600), percent: 10, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-2 * 3600), percent: 20, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-1 * 3600), percent: 30, cycleEnd: cycleEnd),
            snapshot(at: now, percent: 40, cycleEnd: cycleEnd),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[3], now: now, calendar: calendar)
        let pool = stats.pools[.cursorModels]
        XCTAssertEqual(pool?.message, .ready)
        XCTAssertEqual(pool?.paceRatio ?? 0, 10 / 6, accuracy: 0.0001)
        XCTAssertEqual(pool?.exhaustionAt?.timeIntervalSince(now) ?? 0, 6 * 3600, accuracy: 1)
        XCTAssertEqual(pool?.lowConfidence, false)
    }

    func testAtLimitHasNoExhaustion() {
        let cycleEnd = now.addingTimeInterval(10 * 3600)
        let samples = (0..<4).map { index in
            snapshot(at: now.addingTimeInterval(TimeInterval(index - 3) * 3600), percent: 100, cycleEnd: cycleEnd)
        }
        let stats = UsageAnalytics.stats(from: samples, current: samples[3], now: now, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .atLimit)
        XCTAssertNil(stats.pools[.cursorModels]?.exhaustionAt)
    }

    func testResetPendingWhenCycleEnded() {
        let cycleEnd = now.addingTimeInterval(-60)
        let current = snapshot(at: now, percent: 40, cycleEnd: cycleEnd)
        let stats = UsageAnalytics.stats(from: [current], current: current, now: now, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .resetPending)
    }

    func testPercentDropStartsNewSegment() {
        let cycleEnd = now.addingTimeInterval(200 * 3600)
        let samples = [
            snapshot(at: now.addingTimeInterval(-6 * 3600), percent: 80, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-5 * 3600), percent: 90, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-4 * 3600), percent: 10, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-2 * 3600), percent: 11, cycleEnd: cycleEnd),
            snapshot(at: now, percent: 12, cycleEnd: cycleEnd),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[4], now: now, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .ready)
        XCTAssertEqual(stats.pools[.cursorModels]?.paceRatio ?? 0, (0.5 / 3600) / (88 / (200 * 3600)), accuracy: 0.001)
    }

    func testTinyDropIsNoiseAndStaysInSegment() {
        let series: [(Date, Double)] = [
            (now.addingTimeInterval(-3 * 3600), 10),
            (now.addingTimeInterval(-2 * 3600), 9.97),
            (now.addingTimeInterval(-1 * 3600), 11),
        ]
        XCTAssertEqual(UsageAnalytics.currentSegment(series).count, 3)
    }

    func testLongGapMarksLowConfidence() {
        let cycleEnd = now.addingTimeInterval(80 * 3600)
        let samples = [
            snapshot(at: now.addingTimeInterval(-10 * 3600), percent: 10, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-3 * 3600), percent: 20, cycleEnd: cycleEnd),
            snapshot(at: now, percent: 25, cycleEnd: cycleEnd),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[2], now: now, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.lowConfidence, true)
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .ready)
    }

    func testTodayInterpolatesAcrossLocalMidnight() {
        let cycleEnd = now.addingTimeInterval(48 * 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: now)
        let currentTime = midnight.addingTimeInterval(12 * 3600)
        let samples = [
            snapshot(at: midnight.addingTimeInterval(-2 * 3600), percent: 10, cycleEnd: cycleEnd),
            snapshot(at: midnight.addingTimeInterval(2 * 3600), percent: 14, cycleEnd: cycleEnd),
            snapshot(at: currentTime, percent: 20, cycleEnd: cycleEnd),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[2], now: currentTime, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.todayDelta ?? 0, 8, accuracy: 0.0001)
        XCTAssertEqual(stats.pools[.cursorModels]?.todayIsSinceFirstRecord, false)
    }

    func testTodayFallsBackToFirstRecordLabel() {
        let cycleEnd = now.addingTimeInterval(48 * 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: now)
        let currentTime = midnight.addingTimeInterval(6 * 3600)
        let samples = [
            snapshot(at: midnight.addingTimeInterval(1 * 3600), percent: 5, cycleEnd: cycleEnd),
            snapshot(at: currentTime, percent: 8, cycleEnd: cycleEnd),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[1], now: currentTime, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.todayDelta, 3)
        XCTAssertEqual(stats.pools[.cursorModels]?.todayIsSinceFirstRecord, true)
    }

    func testExhaustionAfterResetIsFlagged() {
        let cycleEnd = now.addingTimeInterval(2 * 3600)
        let samples = [
            snapshot(at: now.addingTimeInterval(-3 * 3600), percent: 10, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-2 * 3600), percent: 20, cycleEnd: cycleEnd),
            snapshot(at: now.addingTimeInterval(-1 * 3600), percent: 30, cycleEnd: cycleEnd),
            snapshot(at: now, percent: 40, cycleEnd: cycleEnd),
        ]
        let stats = UsageAnalytics.stats(from: samples, current: samples[3], now: now, calendar: calendar)
        XCTAssertEqual(stats.pools[.cursorModels]?.message, .resetsBeforeExhaustion)
        XCTAssertNil(stats.pools[.cursorModels]?.exhaustionAt)
    }

    private func snapshot(at date: Date, percent: Double, cycleEnd: Date? = nil) -> UsageSnapshot {
        let end = cycleEnd ?? date.addingTimeInterval(30 * 24 * 3600)
        let start = end.addingTimeInterval(-30 * 24 * 3600)
        return UsageSnapshot(
            providerID: "cursor",
            accountFingerprint: "aaa",
            capturedAt: date,
            cycleStart: start,
            cycleEnd: end,
            buckets: [
                UsageBucket(id: .cursorModels, meter: .metered(percentUsed: percent, absolute: nil)),
            ],
            membershipType: "pro_plus",
            limitType: "user",
            totalPercentUsed: nil
        )
    }
}