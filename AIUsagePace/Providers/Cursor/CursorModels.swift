import Foundation

struct CursorUsageSummaryResponse: Decodable, Sendable {
    var billingCycleStart: String?
    var billingCycleEnd: String?
    var membershipType: String?
    var limitType: String?
    var isUnlimited: Bool?
    var individualUsage: CursorIndividualUsage?
    var teamUsage: CursorTeamUsage?
}

struct CursorIndividualUsage: Decodable, Sendable {
    var plan: CursorPlanUsage?
    var onDemand: CursorOnDemandUsage?
    var overall: CursorOverallUsage?
}

struct CursorPlanUsage: Decodable, Sendable {
    var enabled: Bool?
    var used: Int?
    var limit: Int?
    var remaining: Int?
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var totalPercentUsed: Double?
}

struct CursorOnDemandUsage: Decodable, Sendable {
    var enabled: Bool?
    var used: Int?
    var limit: Int?
    var remaining: Int?
}

struct CursorOverallUsage: Decodable, Sendable {
    var enabled: Bool?
    var used: Int?
    var limit: Int?
    var remaining: Int?
}

struct CursorTeamUsage: Decodable, Sendable {
    var onDemand: CursorOnDemandUsage?
    var pooled: CursorOverallUsage?
}
