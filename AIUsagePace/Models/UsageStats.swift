import Foundation

struct PoolStats: Equatable, Sendable {
    var todayDelta: Double?
    var todayIsSinceFirstRecord: Bool
    var paceRatio: Double?
    var exhaustionAt: Date?
    var lowConfidence: Bool
    var message: PoolMessage
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
