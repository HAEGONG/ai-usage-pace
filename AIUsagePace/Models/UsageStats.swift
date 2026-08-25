import Foundation

enum PaceConfidence: Equatable, Sendable {
    case low
    case medium
    case high
}

enum UsageCadence: Equatable, Sendable {
    case monthly
    case weekly
}

struct PaceDiagnostics: Equatable, Sendable {
    var cadence: UsageCadence
    var currentObservationDuration: TimeInterval
    var historicalCycleCount: Int
    var minimumObservationDuration: TimeInterval
    var hasAmbiguousUsageGap: Bool
    var historyIsUnstable: Bool
    var usesCycleAverageFallback: Bool
}

struct PoolStats: Equatable, Sendable {
    var todayDelta: Double?
    var todayIsSinceFirstRecord: Bool
    var paceRatio: Double?
    var exhaustionAt: Date?
    var confidence: PaceConfidence
    var paceDiagnostics: PaceDiagnostics
    var message: PoolMessage

    var lowConfidence: Bool {
        confidence == .low
    }
}

enum PoolMessage: Equatable, Sendable {
    case ready
    case notEnoughData
    case atLimit
    case resetPending
    case resetsBeforeExhaustion
    case noExhaustionProjected
}

struct UsageStats: Equatable, Sendable {
    var pools: [UsagePoolID: PoolStats]

    func paceRatio(for pool: UsagePoolID) -> Double? {
        pools[pool]?.paceRatio
    }
}
