import Foundation

enum UsagePoolID: String, Codable, Sendable, CaseIterable {
    case cursorModels
    case otherModels
    case grokBotWeekly
    case grokWeekly

    var title: String {
        switch self {
        case .cursorModels:
            "Cursor Models"
        case .otherModels:
            "Other Models"
        case .grokBotWeekly:
            "Grok Bot"
        case .grokWeekly:
            "Grok CLI"
        }
    }

    var titleLocalizationKey: String {
        switch self {
        case .cursorModels:
            LocalizationKey.usageCursorModels
        case .otherModels:
            LocalizationKey.usageOtherModels
        case .grokBotWeekly:
            LocalizationKey.usageGrokBot
        case .grokWeekly:
            LocalizationKey.usageGrokCLI
        }
    }

    var menuBarPrefix: String {
        switch self {
        case .cursorModels:
            "C"
        case .otherModels:
            "O"
        case .grokBotWeekly:
            "B"
        case .grokWeekly:
            "G"
        }
    }
}

enum UsageUnit: String, Codable, Sendable {
    case cents
    case requests
}

struct AbsoluteUsage: Equatable, Sendable {
    let used: Double
    let limit: Double
    let unit: UsageUnit
}

enum UsageMeter: Equatable, Sendable {
    case metered(percentUsed: Double, absolute: AbsoluteUsage?)
}

struct UsageBucket: Equatable, Sendable {
    let id: UsagePoolID
    let meter: UsageMeter
    let cycleStart: Date?
    let cycleEnd: Date?

    init(
        id: UsagePoolID,
        meter: UsageMeter,
        cycleStart: Date? = nil,
        cycleEnd: Date? = nil
    ) {
        self.id = id
        self.meter = meter
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
    }

    func cycleStart(in snapshot: UsageSnapshot) -> Date? {
        cycleStart ?? snapshot.cycleStart
    }

    func cycleEnd(in snapshot: UsageSnapshot) -> Date? {
        cycleEnd ?? snapshot.cycleEnd
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let providerID: String
    let accountFingerprint: String
    let capturedAt: Date
    let cycleStart: Date?
    let cycleEnd: Date?
    let buckets: [UsageBucket]
    let membershipType: String?
    let limitType: String?
    let totalPercentUsed: Double?
    let poolErrors: [UsagePoolID: AppError]

    init(
        providerID: String,
        accountFingerprint: String,
        capturedAt: Date,
        cycleStart: Date?,
        cycleEnd: Date?,
        buckets: [UsageBucket],
        membershipType: String?,
        limitType: String?,
        totalPercentUsed: Double?,
        poolErrors: [UsagePoolID: AppError] = [:]
    ) {
        self.providerID = providerID
        self.accountFingerprint = accountFingerprint
        self.capturedAt = capturedAt
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.buckets = buckets
        self.membershipType = membershipType
        self.limitType = limitType
        self.totalPercentUsed = totalPercentUsed
        self.poolErrors = poolErrors
    }

    func appending(_ bucket: UsageBucket) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            accountFingerprint: accountFingerprint,
            capturedAt: capturedAt,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            buckets: buckets + [bucket],
            membershipType: membershipType,
            limitType: limitType,
            totalPercentUsed: totalPercentUsed,
            poolErrors: poolErrors
        )
    }

    func withPoolError(_ pool: UsagePoolID, _ error: AppError) -> UsageSnapshot {
        var errors = poolErrors
        errors[pool] = error
        return UsageSnapshot(
            providerID: providerID,
            accountFingerprint: accountFingerprint,
            capturedAt: capturedAt,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            buckets: buckets,
            membershipType: membershipType,
            limitType: limitType,
            totalPercentUsed: totalPercentUsed,
            poolErrors: errors
        )
    }

    func withoutPoolErrors() -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            accountFingerprint: accountFingerprint,
            capturedAt: capturedAt,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            buckets: buckets,
            membershipType: membershipType,
            limitType: limitType,
            totalPercentUsed: totalPercentUsed,
            poolErrors: [:]
        )
    }
}

extension UsageBucket {
    var percentUsed: Double {
        switch meter {
        case .metered(let percentUsed, _):
            return percentUsed
        }
    }

    var progressFraction: Double {
        min(max(percentUsed / 100, 0), 1)
    }
}

enum UsagePercentFormat {
    static func string(_ percentUsed: Double) -> String {
        let roundedToTenth = (percentUsed * 10).rounded() / 10
        if roundedToTenth == roundedToTenth.rounded(.towardZero) {
            return "\(Int(roundedToTenth))%"
        }
        return String(format: "%.1f%%", roundedToTenth)
    }

    static func string(_ percentUsed: Double, locale: Locale) -> String {
        let roundedToTenth = (percentUsed * 10).rounded() / 10
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = roundedToTenth == roundedToTenth.rounded(.towardZero) ? 0 : 1
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: roundedToTenth)) ?? string(percentUsed)
        return "\(value)%"
    }
}

extension UsageSnapshot {
    static let defaultMenuBarTitle = "Usage Pace"

    var highlightedBucket: UsageBucket? {
        Self.highlightedBucket(from: buckets.map { ($0, nil) })
    }

    var menuBarTitle: String {
        Self.menuBarTitle(from: buckets.map { ($0, nil) })
    }

    func menuBarTitle(stats: UsageStats?) -> String {
        Self.menuBarTitle(from: buckets.map { ($0, stats?.paceRatio(for: $0.id)) })
    }

    func menuBarTitle(stats: UsageStats?, locale: Locale) -> String {
        Self.menuBarTitle(
            from: buckets.map { ($0, stats?.paceRatio(for: $0.id)) },
            locale: locale
        )
    }

    func highlightedBucket(stats: UsageStats?) -> UsageBucket? {
        Self.highlightedBucket(from: buckets.map { ($0, stats?.paceRatio(for: $0.id)) })
    }

    static func menuBarTitle(from candidates: [(UsageBucket, Double?)]) -> String {
        guard let bucket = highlightedBucket(from: candidates) else {
            return defaultMenuBarTitle
        }
        return "\(bucket.id.menuBarPrefix) \(UsagePercentFormat.string(bucket.percentUsed))"
    }

    static func menuBarTitle(
        from candidates: [(UsageBucket, Double?)],
        locale: Locale
    ) -> String {
        guard let bucket = highlightedBucket(from: candidates) else {
            return defaultMenuBarTitle
        }
        return "\(bucket.id.menuBarPrefix) \(UsagePercentFormat.string(bucket.percentUsed, locale: locale))"
    }

    static func highlightedBucket(from candidates: [(UsageBucket, Double?)]) -> UsageBucket? {
        let paced = candidates.compactMap { bucket, pace -> (UsageBucket, Double)? in
            guard let pace else { return nil }
            return (bucket, pace)
        }
        if let best = paced.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.id != .cursorModels && rhs.0.id == .cursorModels
        }) {
            return best.0
        }
        return candidates.map(\.0).max { lhs, rhs in
            if lhs.percentUsed != rhs.percentUsed {
                return lhs.percentUsed < rhs.percentUsed
            }
            return lhs.id != .cursorModels && rhs.id == .cursorModels
        }
    }
}
