import XCTest
@testable import AIUsagePace

final class RefreshServiceTests: XCTestCase {
    @MainActor
    func testIgnoresOverlappingRefresh() async {
        let provider = MockUsageProvider(delayNanoseconds: 50_000_000)
        let service = RefreshService(providers: [provider])

        service.refresh()
        service.refresh()
        await service.waitForIdle()

        XCTAssertEqual(provider.fetchCount, 1)
    }

    @MainActor
    func testStartIsIdempotent() async {
        let provider = MockUsageProvider()
        let service = RefreshService(providers: [provider])
        provider.nextSnapshot = .stub(fingerprint: "aaa", percent: 10)

        service.start()
        await service.waitForIdle()
        service.start()
        await service.waitForIdle()

        XCTAssertEqual(provider.fetchCount, 1)
    }

    @MainActor
    func testAccountSwitchDoesNotShowPreviousAccountOnFetchFailure() async {
        let provider = MockUsageProvider()
        let service = RefreshService(providers: [provider])

        provider.nextSnapshot = .stub(fingerprint: "aaa", percent: 10)
        await service.performRefresh()
        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.accountFingerprint, "aaa")

        provider.fingerprint = "bbb"
        provider.nextError = .networkFailure
        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.activeFingerprint, "bbb")
        XCTAssertNil(service.state(id: "cursor")?.snapshot)
        XCTAssertEqual(service.state(id: "cursor")?.error, .networkFailure)
    }

    @MainActor
    func testAccountSwitchClearsPreviousErrorWhileCachedUsageRefreshes() async {
        let provider = MockUsageProvider()
        let service = RefreshService(providers: [provider])
        let accountBSnapshot = UsageSnapshot.stub(fingerprint: "bbb", percent: 20)

        provider.fingerprint = "bbb"
        provider.nextSnapshot = accountBSnapshot
        await service.performRefresh()

        provider.fingerprint = "aaa"
        provider.nextError = .authenticationExpired
        await service.performRefresh()
        XCTAssertEqual(service.state(id: "cursor")?.error, .authenticationExpired)

        provider.fingerprint = "bbb"
        provider.nextError = nil
        provider.delayNanoseconds = 200_000_000
        service.refresh()

        while provider.fetchCount < 3 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(service.state(id: "cursor")?.snapshot, accountBSnapshot)
        XCTAssertNil(service.state(id: "cursor")?.error)

        await service.waitForIdle()
    }

    @MainActor
    func testWakeTriggersRefreshWhenIdle() async {
        let provider = MockUsageProvider()
        let service = RefreshService(providers: [provider])
        provider.nextSnapshot = .stub(fingerprint: "aaa", percent: 10)

        service.handleDidWake()
        await service.waitForIdle()

        XCTAssertEqual(provider.fetchCount, 1)
    }

    @MainActor
    func testNetworkFailureUsesExponentialBackoff() async {
        let provider = MockUsageProvider()
        let service = RefreshService(providers: [provider])
        provider.nextError = .networkFailure

        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.minimumBackoff)

        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.minimumBackoff * 2)

        provider.nextError = nil
        provider.nextSnapshot = .stub(fingerprint: "aaa", percent: 4)
        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.defaultRefreshInterval)
    }

    @MainActor
    func testNetworkFailureKeepsLastSuccessfulSnapshot() async {
        let provider = MockUsageProvider()
        let service = RefreshService(providers: [provider])
        let first = UsageSnapshot.stub(
            fingerprint: "aaa",
            percent: 22,
            capturedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )
        provider.nextSnapshot = first
        await service.performRefresh()

        provider.nextError = .networkFailure
        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.snapshot, first)
        XCTAssertEqual(service.state(id: "cursor")?.error, .networkFailure)
        XCTAssertEqual(service.state(id: "cursor")?.lastUpdated, first.capturedAt)
    }

    @MainActor
    func testNetworkFailureKeepsLastSuccessfulStats() async throws {
        let provider = MockUsageProvider()
        let capturedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let cycleStart = capturedAt.addingTimeInterval(-20 * 24 * 3600)
        let cycleEnd = capturedAt.addingTimeInterval(10 * 24 * 3600)

        func snapshot(hoursBefore: TimeInterval, percent: Double) -> UsageSnapshot {
            UsageSnapshot(
                providerID: "cursor",
                accountFingerprint: "aaa",
                capturedAt: capturedAt.addingTimeInterval(-hoursBefore * 3600),
                cycleStart: cycleStart,
                cycleEnd: cycleEnd,
                buckets: [
                    UsageBucket(id: .cursorModels, meter: .metered(percentUsed: percent, absolute: nil)),
                ],
                membershipType: "pro",
                limitType: "user",
                totalPercentUsed: nil
            )
        }

        let history = InMemoryUsageHistory(records: [
            snapshot(hoursBefore: 72, percent: 10),
            snapshot(hoursBefore: 48, percent: 20),
            snapshot(hoursBefore: 24, percent: 30),
        ])
        let service = RefreshService(providers: [provider], history: history)
        provider.nextSnapshot = snapshot(hoursBefore: 0, percent: 40)

        await service.performRefresh()
        let successfulStats = try XCTUnwrap(service.state(id: "cursor")?.stats)
        XCTAssertEqual(successfulStats.pools[.cursorModels]?.message, .ready)

        try await Task.sleep(nanoseconds: 20_000_000)
        provider.nextError = .networkFailure
        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.stats, successfulStats)
    }

    @MainActor
    func testHistoryFailureKeepsCurrentUsageAndShowsWarning() async {
        let provider = MockUsageProvider()
        let service = RefreshService(
            providers: [provider],
            history: FailingUsageHistory()
        )
        let snapshot = UsageSnapshot.stub(fingerprint: "aaa", percent: 22)
        provider.nextSnapshot = snapshot

        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.snapshot, snapshot)
        XCTAssertNil(service.state(id: "cursor")?.error)
        XCTAssertEqual(service.state(id: "cursor")?.historyWarning, .usageHistoryUnavailable)
    }

    @MainActor
    func testGrokLoginMissingDoesNotClearCursorUsage() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        let snapshot = UsageSnapshot.stub(fingerprint: "aaa", percent: 12)
        cursor.nextSnapshot = snapshot
        grok.fingerprintError = .grokLoginNotFound

        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.snapshot, snapshot)
        XCTAssertNil(service.state(id: "cursor")?.error)
        XCTAssertNil(service.state(id: "grok")?.snapshot)
        XCTAssertEqual(service.state(id: "grok")?.error, .grokLoginNotFound)
        XCTAssertEqual(grok.fetchCount, 0)
        XCTAssertEqual(service.menuBarTitle, "C 12%")
    }

    @MainActor
    func testCursorMissingDoesNotClearGrokUsage() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        cursor.fingerprintError = .cursorLoginNotFound
        grok.nextSnapshot = .grokStub(fingerprint: "ggg", percent: 42.5)

        await service.performRefresh()

        XCTAssertNil(service.state(id: "cursor")?.snapshot)
        XCTAssertEqual(service.state(id: "cursor")?.error, .cursorLoginNotFound)
        XCTAssertEqual(service.state(id: "grok")?.snapshot?.buckets.first?.percentUsed, 42.5)
        XCTAssertNil(service.state(id: "grok")?.error)
        XCTAssertEqual(service.menuBarTitle, "G 42.5%")
    }

    @MainActor
    func testPartialNetworkFailureBacksOffEvenWhenOtherProviderSucceeds() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        cursor.nextSnapshot = .stub(fingerprint: "aaa", percent: 8)
        grok.nextError = .networkFailure

        await service.performRefresh()

        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.minimumBackoff)
        XCTAssertEqual(service.state(id: "grok")?.error, .networkFailure)
        XCTAssertNotNil(service.state(id: "cursor")?.snapshot)

        // A repeated partial failure keeps growing the backoff for the failing
        // provider instead of waiting the full default interval.
        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.minimumBackoff * 2)

        // Once no provider reports a network failure, the interval resets.
        grok.nextError = nil
        grok.nextSnapshot = .grokStub(fingerprint: "ggg", percent: 30)
        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.defaultRefreshInterval)
    }

    @MainActor
    func testCursorAccountSwitchReplacesGrokBotAndLeavesGrokCLI() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok CLI", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        grok.nextSnapshot = .grokStub(fingerprint: "ggg", percent: 42.5)
        cursor.nextSnapshot = .cursorWithGrokBot(fingerprint: "aaa", cursorPercent: 10, grokBotPercent: 80)

        await service.performRefresh()
        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.buckets.first { $0.id == .grokBotWeekly }?.percentUsed, 80)
        let grokSnapshot = service.state(id: "grok")?.snapshot

        cursor.fingerprint = "bbb"
        cursor.nextSnapshot = .cursorWithGrokBot(fingerprint: "bbb", cursorPercent: 5, grokBotPercent: 15)
        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.accountFingerprint, "bbb")
        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.buckets.first { $0.id == .grokBotWeekly }?.percentUsed, 15)
        XCTAssertEqual(service.state(id: "grok")?.snapshot, grokSnapshot)
        XCTAssertNil(service.state(id: "grok")?.error)
    }

    @MainActor
    func testCursorLogoutClearsGrokBotAndLeavesGrokCLI() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok CLI", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        cursor.nextSnapshot = .cursorWithGrokBot(fingerprint: "aaa", cursorPercent: 10, grokBotPercent: 80)
        grok.nextSnapshot = .grokStub(fingerprint: "ggg", percent: 42.5)
        await service.performRefresh()

        cursor.fingerprintError = .cursorLoginNotFound
        await service.performRefresh()

        XCTAssertNil(service.state(id: "cursor")?.snapshot)
        XCTAssertEqual(service.state(id: "cursor")?.error, .cursorLoginNotFound)
        XCTAssertEqual(service.state(id: "grok")?.snapshot?.buckets.first?.percentUsed, 42.5)
        XCTAssertNil(service.state(id: "grok")?.error)
    }

    @MainActor
    func testGrokBotPoolErrorDoesNotFailCursorOrGrokCLI() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok CLI", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        cursor.nextSnapshot = UsageSnapshot.stub(fingerprint: "aaa", percent: 8)
            .withPoolError(.grokBotWeekly, .authenticationExpired)
        grok.nextSnapshot = .grokStub(fingerprint: "ggg", percent: 42.5)

        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.buckets.map(\.id), [.cursorModels])
        XCTAssertNil(service.state(id: "cursor")?.error)
        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.poolErrors[.grokBotWeekly], .authenticationExpired)
        XCTAssertEqual(service.state(id: "grok")?.snapshot?.buckets.first?.id, .grokWeekly)
        XCTAssertNil(service.state(id: "grok")?.error)
    }

    @MainActor
    func testGrokCLIFailureKeepsGrokBot() async {
        let cursor = MockUsageProvider()
        let grok = MockUsageProvider(id: "grok", displayName: "Grok CLI", fingerprint: "ggg")
        let service = RefreshService(providers: [cursor, grok])
        cursor.nextSnapshot = .cursorWithGrokBot(fingerprint: "aaa", cursorPercent: 10, grokBotPercent: 80)
        grok.nextError = .networkFailure

        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.snapshot?.buckets.first { $0.id == .grokBotWeekly }?.percentUsed, 80)
        XCTAssertNil(service.state(id: "cursor")?.error)
        XCTAssertEqual(service.state(id: "grok")?.error, .networkFailure)
    }

    @MainActor
    func testPreviousCursorAccountGrokBotIsNotShownAfterSwitchFailure() async {
        let cursor = MockUsageProvider()
        let service = RefreshService(providers: [cursor])
        cursor.nextSnapshot = .cursorWithGrokBot(fingerprint: "aaa", cursorPercent: 10, grokBotPercent: 80)
        await service.performRefresh()

        cursor.fingerprint = "bbb"
        cursor.nextError = .networkFailure
        await service.performRefresh()

        XCTAssertEqual(service.state(id: "cursor")?.activeFingerprint, "bbb")
        XCTAssertNil(service.state(id: "cursor")?.snapshot)
        XCTAssertEqual(service.state(id: "cursor")?.error, .networkFailure)
    }
}

private struct FailingUsageHistory: UsageHistoryWriting {
    func record(_ snapshot: UsageSnapshot) async throws {
        throw AppError.usageHistoryUnavailable
    }

    func snapshots(for fingerprint: String) async throws -> [UsageSnapshot] {
        throw AppError.usageHistoryUnavailable
    }
}

private actor InMemoryUsageHistory: UsageHistoryWriting {
    private var records: [UsageSnapshot]

    init(records: [UsageSnapshot]) {
        self.records = records
    }

    func record(_ snapshot: UsageSnapshot) async throws {
        records.append(snapshot)
    }

    func snapshots(for fingerprint: String) async throws -> [UsageSnapshot] {
        records.filter { $0.accountFingerprint == fingerprint }
    }
}

private final class MockUsageProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    var fingerprint: String
    var fingerprintError: AppError?
    var fetchCount = 0
    var delayNanoseconds: UInt64
    var nextSnapshot: UsageSnapshot?
    var nextError: AppError?

    init(
        id: String = "cursor",
        displayName: String = "Cursor",
        fingerprint: String = "aaa",
        delayNanoseconds: UInt64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.fingerprint = fingerprint
        self.delayNanoseconds = delayNanoseconds
    }

    func loadSession() async throws -> ProviderSession {
        if let fingerprintError {
            throw fingerprintError
        }
        let fingerprint = fingerprint
        return ProviderSession(accountFingerprint: fingerprint) { [self] in
            fetchCount += 1
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if let nextError {
                throw nextError
            }
            guard let nextSnapshot else {
                throw AppError.usageUnavailable
            }
            return nextSnapshot
        }
    }
}

extension CursorSession {
    static let accountA = CursorSession(
        accessToken: "token-a",
        userID: "user_a",
        subject: "github|user_a",
        accountFingerprint: "aaa"
    )

    static let accountB = CursorSession(
        accessToken: "token-b",
        userID: "user_b",
        subject: "github|user_b",
        accountFingerprint: "bbb"
    )
}

extension UsageSnapshot {
    static func stub(fingerprint: String, percent: Double, capturedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            providerID: "cursor",
            accountFingerprint: fingerprint,
            capturedAt: Date(timeIntervalSince1970: capturedAt.timeIntervalSince1970.rounded()),
            cycleStart: nil,
            cycleEnd: nil,
            buckets: [
                UsageBucket(id: .cursorModels, meter: .metered(percentUsed: percent, absolute: nil)),
            ],
            membershipType: "pro",
            limitType: nil,
            totalPercentUsed: nil
        )
    }

    static func grokStub(fingerprint: String, percent: Double, capturedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            providerID: "grok",
            accountFingerprint: fingerprint,
            capturedAt: Date(timeIntervalSince1970: capturedAt.timeIntervalSince1970.rounded()),
            cycleStart: nil,
            cycleEnd: nil,
            buckets: [
                UsageBucket(id: .grokWeekly, meter: .metered(percentUsed: percent, absolute: nil)),
            ],
            membershipType: "unified",
            limitType: GrokUsageMapper.weeklyPeriodType,
            totalPercentUsed: nil
        )
    }

    static func cursorWithGrokBot(
        fingerprint: String,
        cursorPercent: Double,
        grokBotPercent: Double,
        capturedAt: Date = Date()
    ) -> UsageSnapshot {
        let captured = Date(timeIntervalSince1970: capturedAt.timeIntervalSince1970.rounded())
        let monthlyStart = captured.addingTimeInterval(-20 * 24 * 3600)
        let monthlyEnd = captured.addingTimeInterval(10 * 24 * 3600)
        let weeklyStart = captured.addingTimeInterval(-3 * 24 * 3600)
        let weeklyEnd = captured.addingTimeInterval(4 * 24 * 3600)
        return UsageSnapshot(
            providerID: "cursor",
            accountFingerprint: fingerprint,
            capturedAt: captured,
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
                    id: .otherModels,
                    meter: .metered(percentUsed: 0, absolute: nil),
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

extension RefreshService {
    func waitForIdle() async {
        while isRefreshing {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
