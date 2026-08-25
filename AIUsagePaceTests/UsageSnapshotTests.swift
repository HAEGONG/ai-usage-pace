import XCTest
@testable import AIUsagePace

final class UsageSnapshotTests: XCTestCase {
    func testMenuBarUsesHigherPercentPool() {
        XCTAssertEqual(
            snapshot(cursor: 10, other: 80).menuBarTitle,
            "O 80%"
        )
        XCTAssertEqual(
            snapshot(cursor: 62, other: 11).menuBarTitle,
            "C 62%"
        )
    }

    func testMenuBarPrefersCursorModelsWhenPercentsTie() {
        XCTAssertEqual(
            snapshot(cursor: 0, other: 0).menuBarTitle,
            "C 0%"
        )
    }

    func testMenuBarKeepsFractionWhenRoundedIntegerWouldHideUsage() {
        XCTAssertEqual(
            snapshot(cursor: 0.5308333333333334, other: 0).menuBarTitle,
            "C 0.5%"
        )
    }

    func testMenuBarPrefersHigherPaceRatioWhenAvailable() {
        let usage = snapshot(cursor: 90, other: 10)
        let stats = UsageStats(pools: [
            .cursorModels: PoolStats(
                todayDelta: nil,
                todayIsSinceFirstRecord: false,
                paceRatio: 0.5,
                exhaustionAt: nil,
                lowConfidence: false,
                message: .ready
            ),
            .otherModels: PoolStats(
                todayDelta: nil,
                todayIsSinceFirstRecord: false,
                paceRatio: 2.0,
                exhaustionAt: nil,
                lowConfidence: false,
                message: .ready
            ),
        ])
        XCTAssertEqual(usage.menuBarTitle(stats: stats), "O 10%")
    }

    func testProgressBarClampsPercentOverOneHundred() {
        XCTAssertEqual(
            UsageBucket(id: .cursorModels, meter: .metered(percentUsed: 150, absolute: nil)).progressFraction,
            1
        )
    }

    private func snapshot(cursor: Double, other: Double) -> UsageSnapshot {
        UsageSnapshot(
            providerID: "cursor",
            accountFingerprint: "aaa",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cycleStart: nil,
            cycleEnd: nil,
            buckets: [
                UsageBucket(id: .cursorModels, meter: .metered(percentUsed: cursor, absolute: nil)),
                UsageBucket(id: .otherModels, meter: .metered(percentUsed: other, absolute: nil)),
            ],
            membershipType: "pro_plus",
            limitType: "user",
            totalPercentUsed: nil
        )
    }
}