import AppKit
import Combine
import Foundation

struct ProviderUsageState: Equatable, Identifiable, Sendable {
    var id: String { providerID }
    let providerID: String
    let displayName: String
    var snapshot: UsageSnapshot?
    var stats: UsageStats?
    var error: AppError?
    var historyWarning: AppError?
    var lastUpdated: Date?
    var activeFingerprint: String?
}

@MainActor
final class RefreshService: ObservableObject {
    static let defaultRefreshInterval: TimeInterval = 15 * 60
    static let minimumBackoff: TimeInterval = 30
    static let maximumBackoff: TimeInterval = 15 * 60

    @Published private(set) var providerStates: [ProviderUsageState]

    private let providers: [any UsageProvider]
    private let history: any UsageHistoryWriting
    private var lastSuccessByKey: [String: UsageSnapshot] = [:]
    private var inFlightTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var backoffInterval: TimeInterval = 0
    private var hasStarted = false
    private(set) var scheduledRefreshInterval: TimeInterval?

    init(
        providers: [any UsageProvider],
        history: any UsageHistoryWriting = NoOpUsageHistory()
    ) {
        self.providers = providers
        self.history = history
        self.providerStates = providers.map {
            ProviderUsageState(providerID: $0.id, displayName: $0.displayName)
        }
    }

    var isRefreshing: Bool {
        inFlightTask != nil
    }

    var highlightedBucket: UsageBucket? {
        UsageSnapshot.highlightedBucket(from: menuBarCandidates)
    }

    var menuBarIconAssetName: String? {
        highlightedBucket?.id.iconAssetName
    }

    var menuBarTitle: String {
        UsageSnapshot.menuBarTitle(from: menuBarCandidates)
    }

    func menuBarTitle(locale: Locale) -> String {
        UsageSnapshot.menuBarTitle(from: menuBarCandidates, locale: locale)
    }

    private var menuBarCandidates: [(UsageBucket, Double?)] {
        providerStates.flatMap { state in
            (state.snapshot?.buckets ?? []).map { ($0, state.stats?.paceRatio(for: $0.id)) }
        }
    }

    func state(id: String) -> ProviderUsageState? {
        providerStates.first { $0.providerID == id }
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

        // Start every provider request concurrently so a slow or timing-out
        // provider does not delay the others; each result is applied to its own
        // provider state on the MainActor as it completes.
        let outcomes = await withTaskGroup(of: ProviderRefreshOutcome.self) { group in
            for provider in providers {
                group.addTask { await self.refreshProvider(provider) }
            }
            var collected: [ProviderRefreshOutcome] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        // A network failure on any provider triggers a fast backoff retry, even
        // when another provider succeeded. Otherwise a provider that keeps
        // failing (while another keeps succeeding) would never be retried before
        // the next full interval.
        if outcomes.contains(.networkFailure) {
            scheduleNextRefresh(after: nextBackoffInterval())
        } else {
            backoffInterval = 0
            scheduleNextRefresh(after: Self.defaultRefreshInterval)
        }
    }

    private enum ProviderRefreshOutcome {
        case success
        case networkFailure
        case other
    }

    private func refreshProvider(_ provider: any UsageProvider) async -> ProviderRefreshOutcome {
        let session: ProviderSession
        do {
            session = try await provider.loadSession()
        } catch let appError as AppError {
            applyIdentityFailure(providerID: provider.id, error: appError)
            return appError == .networkFailure ? .networkFailure : .other
        } catch {
            applyIdentityFailure(providerID: provider.id, error: identityError(for: provider.id))
            return .other
        }

        let fingerprint = session.accountFingerprint
        updateIdentity(providerID: provider.id, fingerprint: fingerprint)

        do {
            let snapshot = try await session.fetchUsage()
            let key = successKey(providerID: provider.id, fingerprint: snapshot.accountFingerprint)
            lastSuccessByKey[key] = snapshot.withoutPoolErrors()
            updateState(providerID: provider.id) { state in
                state.activeFingerprint = snapshot.accountFingerprint
                state.snapshot = snapshot
                state.lastUpdated = snapshot.capturedAt
                state.error = nil
            }
            await recordAndUpdateStats(providerID: provider.id, snapshot: snapshot)
            return .success
        } catch let appError as AppError {
            applyFetchFailure(providerID: provider.id, fingerprint: fingerprint, error: appError)
            return appError == .networkFailure ? .networkFailure : .other
        } catch {
            applyFetchFailure(providerID: provider.id, fingerprint: fingerprint, error: .networkFailure)
            return .networkFailure
        }
    }

    private func applyIdentityFailure(providerID: String, error: AppError) {
        updateState(providerID: providerID) { state in
            state.snapshot = nil
            state.activeFingerprint = nil
            state.stats = nil
            state.historyWarning = nil
            state.lastUpdated = nil
            state.error = error
        }
    }

    private func updateIdentity(providerID: String, fingerprint: String) {
        updateState(providerID: providerID) { state in
            if state.activeFingerprint != fingerprint {
                state.activeFingerprint = fingerprint
                state.snapshot = lastSuccessByKey[successKey(providerID: providerID, fingerprint: fingerprint)]
                state.lastUpdated = state.snapshot?.capturedAt
                state.stats = nil
                state.error = nil
                state.historyWarning = nil
            }
        }
    }

    private func applyFetchFailure(providerID: String, fingerprint: String, error: AppError) {
        updateState(providerID: providerID) { state in
            state.snapshot = lastSuccessByKey[successKey(providerID: providerID, fingerprint: fingerprint)]
            state.lastUpdated = state.snapshot?.capturedAt
            state.error = error
        }
    }

    private func identityError(for providerID: String) -> AppError {
        switch providerID {
        case "grok": .unableToReadGrokSession
        case "codex": .unableToReadCodexSession
        default: .unableToReadCursorSession
        }
    }

    private func successKey(providerID: String, fingerprint: String) -> String {
        "\(providerID):\(fingerprint)"
    }

    private func updateState(providerID: String, mutate: (inout ProviderUsageState) -> Void) {
        guard let index = providerStates.firstIndex(where: { $0.providerID == providerID }) else {
            return
        }
        mutate(&providerStates[index])
    }

    private func updateStats(providerID: String, snapshot: UsageSnapshot?) async {
        guard let snapshot else {
            updateState(providerID: providerID) { state in
                state.stats = nil
                state.historyWarning = nil
            }
            return
        }
        do {
            let records = try await history.snapshots(for: snapshot.accountFingerprint)
            updateState(providerID: providerID) { state in
                state.stats = UsageAnalytics.stats(from: records, current: snapshot, now: Date())
                state.historyWarning = nil
            }
        } catch {
            updateState(providerID: providerID) { state in
                state.stats = nil
                state.historyWarning = .usageHistoryUnavailable
            }
        }
    }

    private func recordAndUpdateStats(providerID: String, snapshot: UsageSnapshot) async {
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
            updateState(providerID: providerID) { state in
                state.stats = UsageAnalytics.stats(from: records, current: snapshot, now: Date())
                state.historyWarning = couldRecord ? nil : .usageHistoryUnavailable
            }
        } catch {
            updateState(providerID: providerID) { state in
                state.stats = nil
                state.historyWarning = .usageHistoryUnavailable
            }
        }
    }

    private func nextBackoffInterval() -> TimeInterval {
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
