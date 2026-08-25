import Foundation

struct GrokBillingResponse: Decodable, Sendable {
    var config: GrokBillingConfig?
}

struct GrokBillingConfig: Decodable, Sendable {
    var creditUsagePercent: Double?
    var currentPeriod: GrokUsagePeriod?
    var billingPeriodStart: String?
    var billingPeriodEnd: String?
    var isUnifiedBillingUser: Bool?
}

struct GrokUsagePeriod: Decodable, Sendable {
    var type: String?
    var start: String?
    var end: String?
}
