import XCTest
@testable import AIUsagePace

final class RefreshServiceTests: XCTestCase {
    @MainActor
    func testIgnoresOverlappingRefresh() async {
        let provider = MockUsageProvider(delayNanoseconds: 50_000_000)
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(sessionLoader: loader, provider: provider)

        service.refresh()
        service.refresh()
        await service.waitForIdle()

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(provider.receivedSessions, [.accountA])
    }

    @MainActor
    func testStartIsIdempotent() async {
        let provider = MockUsageProvider()
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(sessionLoader: loader, provider: provider)
        provider.nextSnapshot = .stub(fingerprint: CursorSession.accountA.accountFingerprint, percent: 10)

        service.start()
        await service.waitForIdle()
        service.start()
        await service.waitForIdle()

        XCTAssertEqual(provider.fetchCount, 1)
    }

    @MainActor
    func testAccountSwitchDoesNotShowPreviousAccountOnFetchFailure() async {
        let provider = MockUsageProvider()
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(sessionLoader: loader, provider: provider)

        provider.nextSnapshot = .stub(fingerprint: CursorSession.accountA.accountFingerprint, percent: 10)
        await service.performRefresh()
        XCTAssertEqual(service.displayedSnapshot?.accountFingerprint, CursorSession.accountA.accountFingerprint)

        loader.session = .accountB
        provider.nextError = .networkFailure
        await service.performRefresh()

        XCTAssertEqual(service.activeFingerprint, CursorSession.accountB.accountFingerprint)
        XCTAssertNil(service.displayedSnapshot)
        XCTAssertEqual(service.error, .networkFailure)
    }

    @MainActor
    func testWakeTriggersRefreshWhenIdle() async {
        let provider = MockUsageProvider()
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(sessionLoader: loader, provider: provider)
        provider.nextSnapshot = .stub(fingerprint: CursorSession.accountA.accountFingerprint, percent: 10)

        service.handleDidWake()
        await service.waitForIdle()

        XCTAssertEqual(provider.fetchCount, 1)
    }

    @MainActor
    func testNetworkFailureUsesExponentialBackoff() async {
        let provider = MockUsageProvider()
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(sessionLoader: loader, provider: provider)
        provider.nextError = .networkFailure

        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.minimumBackoff)

        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.minimumBackoff * 2)

        provider.nextError = nil
        provider.nextSnapshot = .stub(fingerprint: CursorSession.accountA.accountFingerprint, percent: 4)
        await service.performRefresh()
        XCTAssertEqual(service.scheduledRefreshInterval, RefreshService.defaultRefreshInterval)
    }

    @MainActor
    func testNetworkFailureKeepsLastSuccessfulSnapshot() async {
        let provider = MockUsageProvider()
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(sessionLoader: loader, provider: provider)
        let first = UsageSnapshot.stub(
            fingerprint: CursorSession.accountA.accountFingerprint,
            percent: 22,
            capturedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )
        provider.nextSnapshot = first
        await service.performRefresh()

        provider.nextError = .networkFailure
        await service.performRefresh()

        XCTAssertEqual(service.displayedSnapshot, first)
        XCTAssertEqual(service.error, .networkFailure)
        XCTAssertEqual(service.lastUpdated, first.capturedAt)
    }

    @MainActor
    func testHistoryFailureKeepsCurrentUsageAndShowsWarning() async {
        let provider = MockUsageProvider()
        let loader = MockSessionLoader(session: .accountA)
        let service = RefreshService(
            sessionLoader: loader,
            provider: provider,
            history: FailingUsageHistory()
        )
        let snapshot = UsageSnapshot.stub(
            fingerprint: CursorSession.accountA.accountFingerprint,
            percent: 22
        )
        provider.nextSnapshot = snapshot

        await service.performRefresh()

        XCTAssertEqual(service.displayedSnapshot, snapshot)
        XCTAssertNil(service.error)
        XCTAssertEqual(service.historyWarning, .usageHistoryUnavailable)
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

private final class MockSessionLoader: SessionLoading, @unchecked Sendable {
    var session: CursorSession

    init(session: CursorSession) {
        self.session = session
    }

    func loadSession() async throws -> CursorSession {
        session
    }
}

private final class MockUsageProvider: UsageProvider, @unchecked Sendable {
    let id = "cursor"
    let displayName = "Cursor"
    var fetchCount = 0
    var delayNanoseconds: UInt64 = 0
    var nextSnapshot: UsageSnapshot?
    var nextError: AppError?
    var receivedSessions: [CursorSession] = []

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchUsage(session: CursorSession) async throws -> UsageSnapshot {
        fetchCount += 1
        receivedSessions.append(session)
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
}

extension RefreshService {
    func waitForIdle() async {
        while isRefreshing {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
