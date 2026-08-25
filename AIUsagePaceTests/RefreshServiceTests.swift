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
}

private struct FailingUsageHistory: UsageHistoryWriting {
    func record(_ snapshot: UsageSnapshot) async throws {
        throw AppError.usageHistoryUnavailable
    }

    func snapshots(for fingerprint: String) async throws -> [UsageSnapshot] {
        throw AppError.usageHistoryUnavailable
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
}

extension RefreshService {
    func waitForIdle() async {
        while isRefreshing {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
