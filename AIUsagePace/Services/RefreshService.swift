import AppKit
import Combine
import Foundation

@MainActor
final class RefreshService: ObservableObject {
    static let defaultRefreshInterval: TimeInterval = 15 * 60
    static let minimumBackoff: TimeInterval = 30
    static let maximumBackoff: TimeInterval = 15 * 60

    @Published private(set) var displayedSnapshot: UsageSnapshot?
    @Published private(set) var stats: UsageStats?
    @Published private(set) var error: AppError?
    @Published private(set) var historyWarning: AppError?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var activeFingerprint: String?

    private let sessionLoader: any SessionLoading
    private let provider: any UsageProvider
    private let history: any UsageHistoryWriting
    private var lastSuccessByFingerprint: [String: UsageSnapshot] = [:]
    private var inFlightTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var backoffInterval: TimeInterval = 0
    private var hasStarted = false
    private(set) var scheduledRefreshInterval: TimeInterval?

    init(
        sessionLoader: any SessionLoading,
        provider: any UsageProvider,
        history: any UsageHistoryWriting = NoOpUsageHistory()
    ) {
        self.sessionLoader = sessionLoader
        self.provider = provider
        self.history = history
    }

    var isRefreshing: Bool {
        inFlightTask != nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidWake()
            }
        }
        refresh()
    }

    func handleDidWake() {
        refresh()
    }

    func refresh() {
        guard inFlightTask == nil else { return }
        inFlightTask = Task { await performRefresh() }
    }

    func performRefresh() async {
        defer { inFlightTask = nil }

        let session: CursorSession
        do {
            session = try await sessionLoader.loadSession()
        } catch let appError as AppError {
            displayedSnapshot = nil
            activeFingerprint = nil
            stats = nil
            historyWarning = nil
            error = appError
            scheduleNextRefresh(after: Self.defaultRefreshInterval)
            return
        } catch {
            displayedSnapshot = nil
            activeFingerprint = nil
            stats = nil
            historyWarning = nil
            self.error = .unableToReadCursorSession
            scheduleNextRefresh(after: Self.defaultRefreshInterval)
            return
        }

        if activeFingerprint != session.accountFingerprint {
            activeFingerprint = session.accountFingerprint
            displayedSnapshot = lastSuccessByFingerprint[session.accountFingerprint]
            lastUpdated = displayedSnapshot?.capturedAt
            stats = nil
            error = nil
            historyWarning = nil
        }

        do {
            let snapshot = try await provider.fetchUsage(session: session)
            lastSuccessByFingerprint[snapshot.accountFingerprint] = snapshot
            activeFingerprint = snapshot.accountFingerprint
            displayedSnapshot = snapshot
            lastUpdated = snapshot.capturedAt
            error = nil
            backoffInterval = 0
            await recordAndUpdateStats(from: snapshot)
            scheduleNextRefresh(after: Self.defaultRefreshInterval)
        } catch let appError as AppError {
            displayedSnapshot = lastSuccessByFingerprint[session.accountFingerprint]
            lastUpdated = displayedSnapshot?.capturedAt
            error = appError
            await updateStats(from: displayedSnapshot)
            scheduleNextRefresh(after: nextInterval(after: appError))
        } catch {
            displayedSnapshot = lastSuccessByFingerprint[session.accountFingerprint]
            lastUpdated = displayedSnapshot?.capturedAt
            self.error = .networkFailure
            await updateStats(from: displayedSnapshot)
            scheduleNextRefresh(after: nextInterval(after: .networkFailure))
        }
    }

    private func updateStats(from snapshot: UsageSnapshot?) async {
        guard let snapshot else {
            stats = nil
            historyWarning = nil
            return
        }
        do {
            let records = try await history.snapshots(for: snapshot.accountFingerprint)
            stats = UsageAnalytics.stats(from: records, current: snapshot, now: Date())
            historyWarning = nil
        } catch {
            stats = nil
            historyWarning = .usageHistoryUnavailable
        }
    }

    private func recordAndUpdateStats(from snapshot: UsageSnapshot) async {
        var couldRecord = true
        do {
            try await history.record(snapshot)
        } catch {
            couldRecord = false
        }

        do {
            var records = try await history.snapshots(for: snapshot.accountFingerprint)
            if !couldRecord {
                records.append(snapshot)
            }
            stats = UsageAnalytics.stats(from: records, current: snapshot, now: Date())
            historyWarning = couldRecord ? nil : .usageHistoryUnavailable
        } catch {
            stats = nil
            historyWarning = .usageHistoryUnavailable
        }
    }

    private func nextInterval(after error: AppError) -> TimeInterval {
        guard error == .networkFailure else {
            backoffInterval = 0
            return Self.defaultRefreshInterval
        }
        if backoffInterval == 0 {
            backoffInterval = Self.minimumBackoff
        } else {
            backoffInterval = min(backoffInterval * 2, Self.maximumBackoff)
        }
        return backoffInterval
    }

    private func scheduleNextRefresh(after interval: TimeInterval) {
        timerTask?.cancel()
        scheduledRefreshInterval = interval
        timerTask = Task { [weak self] in
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
