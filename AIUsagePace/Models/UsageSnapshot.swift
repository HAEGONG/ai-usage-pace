import Foundation

enum UsagePoolID: String, Codable, Sendable {
    case cursorModels
    case otherModels

    var title: String {
        switch self {
        case .cursorModels:
            "Cursor Models"
        case .otherModels:
            "Other Models"
        }
    }

    var menuBarPrefix: String {
        switch self {
        case .cursorModels:
            "C"
        case .otherModels:
            "O"
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
        buckets.max { lhs, rhs in
            if lhs.percentUsed != rhs.percentUsed {
                return lhs.percentUsed < rhs.percentUsed
            }
            return lhs.id != .cursorModels && rhs.id == .cursorModels
        }
    }

    var menuBarTitle: String {
        title(for: highlightedBucket)
    }

    func menuBarTitle(stats: UsageStats?) -> String {
        title(for: highlightedBucket(stats: stats))
    }

    func highlightedBucket(stats: UsageStats?) -> UsageBucket? {
        guard let stats else { return highlightedBucket }
        let paced = buckets.compactMap { bucket -> (UsageBucket, Double)? in
            guard let ratio = stats.paceRatio(for: bucket.id) else { return nil }
            return (bucket, ratio)
        }
        if let best = paced.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.id != .cursorModels && rhs.0.id == .cursorModels
        }) {
            return best.0
        }
        return highlightedBucket
    }

    private func title(for bucket: UsageBucket?) -> String {
        guard let bucket else {
            return "Usage Pace"
        }
        return "\(bucket.id.menuBarPrefix) \(UsagePercentFormat.string(bucket.percentUsed))"
    }
}
