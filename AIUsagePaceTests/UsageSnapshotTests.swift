import AppKit
import XCTest
@testable import AIUsagePace

final class UsageSnapshotTests: XCTestCase {
    func testMenuBarUsesHigherPercentPool() {
        let otherHighlighted = snapshot(cursor: 10, other: 80)
        XCTAssertEqual(otherHighlighted.menuBarTitle, "80%")
        XCTAssertEqual(otherHighlighted.highlightedBucket?.id, .otherModels)

        let cursorHighlighted = snapshot(cursor: 62, other: 11)
        XCTAssertEqual(cursorHighlighted.menuBarTitle, "62%")
        XCTAssertEqual(cursorHighlighted.highlightedBucket?.id, .cursorModels)
    }

    func testMenuBarPrefersCursorModelsWhenPercentsTie() {
        let usage = snapshot(cursor: 0, other: 0)
        XCTAssertEqual(usage.menuBarTitle, "0%")
        XCTAssertEqual(usage.highlightedBucket?.id, .cursorModels)
    }

    func testMenuBarKeepsFractionWhenRoundedIntegerWouldHideUsage() {
        XCTAssertEqual(
            snapshot(cursor: 0.5308333333333334, other: 0).menuBarTitle,
            "0.5%"
        )
    }

    func testMenuBarIconsMatchServices() {
        XCTAssertEqual(UsagePoolID.cursorModels.iconAssetName, "CursorIcon")
        XCTAssertEqual(UsagePoolID.otherModels.iconAssetName, "CursorIcon")
        XCTAssertEqual(UsagePoolID.grokBotWeekly.iconAssetName, "GrokIcon")
        XCTAssertEqual(UsagePoolID.grokWeekly.iconAssetName, "GrokIcon")
        XCTAssertEqual(UsagePoolID.codexSession.iconAssetName, "CodexIcon")
        XCTAssertEqual(UsagePoolID.codexWeekly.iconAssetName, "CodexIcon")
    }

    func testMenuBarStatusImageIncludesLoadedIcon() {
        for name in ["CursorIcon", "GrokIcon", "CodexIcon"] {
            XCTAssertNotNil(NSImage(named: name), "Missing menu bar asset \(name)")
        }

        guard let withIcon = MenuBarStatusImage.make(iconName: "CursorIcon", title: "29.6%"),
              let textOnly = MenuBarStatusImage.make(iconName: nil, title: "29.6%")
        else {
            return XCTFail("Failed to render menu bar image")
        }
        XCTAssertGreaterThan(withIcon.size.width, textOnly.size.width)
    }

    func testMenuBarPrefersHigherPaceRatioWhenAvailable() {
        let usage = snapshot(cursor: 90, other: 10)
        let stats = UsageStats(pools: [
            .cursorModels: PoolStats(
                todayDelta: nil,
                todayIsSinceFirstRecord: false,
                paceRatio: 0.5,
                exhaustionAt: nil,
                confidence: .high,
                paceDiagnostics: PaceDiagnostics(
                    cadence: .monthly,
                    currentObservationDuration: 0,
                    historicalCycleCount: 0,
                    minimumObservationDuration: 0,
                    hasAmbiguousUsageGap: false,
                    historyIsUnstable: false,
                    usesCycleAverageFallback: false
                ),
                message: .ready
            ),
            .otherModels: PoolStats(
                todayDelta: nil,
                todayIsSinceFirstRecord: false,
                paceRatio: 2.0,
                exhaustionAt: nil,
                confidence: .high,
                paceDiagnostics: PaceDiagnostics(
                    cadence: .monthly,
                    currentObservationDuration: 0,
                    historicalCycleCount: 0,
                    minimumObservationDuration: 0,
                    hasAmbiguousUsageGap: false,
                    historyIsUnstable: false,
                    usesCycleAverageFallback: false
                ),
                message: .ready
            ),
        ])
        XCTAssertEqual(usage.menuBarTitle(stats: stats), "10%")
        XCTAssertEqual(usage.highlightedBucket(stats: stats)?.id, .otherModels)
    }

    func testProgressBarClampsPercentOverOneHundred() {
        XCTAssertEqual(
            UsageBucket(id: .cursorModels, meter: .metered(percentUsed: 150, absolute: nil)).progressFraction,
            1
        )
    }

    func testMenuBarHighlightsGrokWeekly() {
        let usage = UsageSnapshot(
            providerID: "grok",
            accountFingerprint: "ggg",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cycleStart: nil,
            cycleEnd: nil,
            buckets: [
                UsageBucket(id: .grokWeekly, meter: .metered(percentUsed: 42.5, absolute: nil)),
            ],
            membershipType: "unified",
            limitType: "USAGE_PERIOD_TYPE_WEEKLY",
            totalPercentUsed: nil
        )
        XCTAssertEqual(usage.menuBarTitle, "42.5%")
        XCTAssertEqual(usage.highlightedBucket?.id, .grokWeekly)
        XCTAssertEqual(UsagePoolID.grokWeekly.title, "Grok CLI")
    }

    func testMenuBarHighlightsGrokBot() {
        let usage = UsageSnapshot(
            providerID: "cursor",
            accountFingerprint: "aaa",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cycleStart: nil,
            cycleEnd: nil,
            buckets: [
                UsageBucket(id: .grokBotWeekly, meter: .metered(percentUsed: 12, absolute: nil)),
            ],
            membershipType: "pro_plus",
            limitType: "user",
            totalPercentUsed: nil
        )
        XCTAssertEqual(usage.menuBarTitle, "12%")
        XCTAssertEqual(usage.highlightedBucket?.id, .grokBotWeekly)
        XCTAssertEqual(UsagePoolID.grokBotWeekly.title, "Grok Bot")
    }

    func testMenuBarAcrossProvidersPrefersHigherPercentWhenPaceIsUnknown() {
        let candidates: [(UsageBucket, Double?)] = [
            (UsageBucket(id: .cursorModels, meter: .metered(percentUsed: 10, absolute: nil)), nil),
            (UsageBucket(id: .grokWeekly, meter: .metered(percentUsed: 80, absolute: nil)), nil),
        ]
        XCTAssertEqual(UsageSnapshot.menuBarTitle(from: candidates), "80%")
        XCTAssertEqual(UsageSnapshot.highlightedBucket(from: candidates)?.id, .grokWeekly)
    }

    func testMenuBarAcrossProvidersPrefersPaceWhenAnyPoolHasIt() {
        let candidates: [(UsageBucket, Double?)] = [
            (UsageBucket(id: .cursorModels, meter: .metered(percentUsed: 10, absolute: nil)), 2.0),
            (UsageBucket(id: .grokWeekly, meter: .metered(percentUsed: 80, absolute: nil)), nil),
        ]
        XCTAssertEqual(UsageSnapshot.menuBarTitle(from: candidates), "10%")
        XCTAssertEqual(UsageSnapshot.highlightedBucket(from: candidates)?.id, .cursorModels)
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
