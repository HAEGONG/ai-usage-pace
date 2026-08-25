import Foundation

enum UsagePoolID: String, Codable, Sendable {
    case cursorModels
    case otherModels
    case grokWeekly

    var title: String {
        switch self {
        case .cursorModels:
            "Cursor Models"
        case .otherModels:
            "Other Models"
        case .grokWeekly:
            "Weekly"
        }
    }

    var menuBarPrefix: String {
        switch self {
        case .cursorModels:
            "C"
        case .otherModels:
            "O"
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
}

extension UsageSnapshot {
    var highlightedBucket: UsageBucket? {
        Self.highlightedBucket(from: buckets.map { ($0, nil) })
    }

    var menuBarTitle: String {
        Self.menuBarTitle(from: buckets.map { ($0, nil) })
    }

    func menuBarTitle(stats: UsageStats?) -> String {
        Self.menuBarTitle(from: buckets.map { ($0, stats?.paceRatio(for: $0.id)) })
    }

    func highlightedBucket(stats: UsageStats?) -> UsageBucket? {
        Self.highlightedBucket(from: buckets.map { ($0, stats?.paceRatio(for: $0.id)) })
    }

    static func menuBarTitle(from candidates: [(UsageBucket, Double?)]) -> String {
        guard let bucket = highlightedBucket(from: candidates) else {
            return "Usage Pace"
        }
        return "\(bucket.id.menuBarPrefix) \(UsagePercentFormat.string(bucket.percentUsed))"
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
