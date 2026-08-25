import Foundation

protocol UsageHistoryWriting: Sendable {
    func record(_ snapshot: UsageSnapshot) async throws
    func snapshots(for fingerprint: String) async throws -> [UsageSnapshot]
}

actor UsageHistoryStore: UsageHistoryWriting {
    static let schemaVersion = 1
    static let minimumRetention: TimeInterval = 60 * 24 * 60 * 60

    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIUsagePace", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
        self.rootDirectory = rootDirectory ?? defaultRoot
        self.fileManager = fileManager
    }

    func record(_ snapshot: UsageSnapshot) async throws {
        try append(snapshot)
    }

    func snapshots(for fingerprint: String) async throws -> [UsageSnapshot] {
        try load(fingerprint: fingerprint)
    }

    func fileURL(for fingerprint: String) -> URL {
        rootDirectory.appendingPathComponent("\(fingerprint).jsonl")
    }

    func append(_ snapshot: UsageSnapshot, now: Date = Date()) throws {
        try rejectUnsafeFingerprint(snapshot.accountFingerprint)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        var records = try loadRecords(for: snapshot.accountFingerprint)
        records.append(HistoryRecord(snapshot: snapshot))
        records = Self.retained(records, now: now)
        try replaceFile(for: snapshot.accountFingerprint, with: records)
    }

    func load(fingerprint: String) throws -> [UsageSnapshot] {
        try rejectUnsafeFingerprint(fingerprint)
        return try loadRecords(for: fingerprint).map(\.usageSnapshot)
    }

    static func retained(_ records: [HistoryRecord], now: Date) -> [HistoryRecord] {
        let cycleStarts = Set(records.compactMap(\.payload.cycleStart)).sorted()
        let twoCycleSpan = cycleStarts.suffix(2).first.map { now.timeIntervalSince($0) } ?? 0
        let window = max(minimumRetention, twoCycleSpan)
        let cutoff = now.addingTimeInterval(-window)
        return records.filter { $0.payload.capturedAt >= cutoff }
    }

    private func loadRecords(for fingerprint: String) throws -> [HistoryRecord] {
        let url = fileURL(for: fingerprint)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = Self.makeDecoder()
        var records: [HistoryRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let record = try? decoder.decode(HistoryRecord.self, from: data),
                  record.schemaVersion == Self.schemaVersion,
                  record.accountFingerprint == fingerprint
            else {
                continue
            }
            records.append(record)
        }
        return records
    }

    private func replaceFile(for fingerprint: String, with records: [HistoryRecord]) throws {
        let url = fileURL(for: fingerprint)
        let encoder = Self.makeEncoder()
        var body = Data()
        for record in records {
            body.append(try encoder.encode(record))
            body.append(contentsOf: [0x0A])
        }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(fingerprint).jsonl.tmp")
        try body.write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: url)
        }
    }

    private func rejectUnsafeFingerprint(_ fingerprint: String) throws {
        let allowed = CharacterSet.alphanumerics
        guard !fingerprint.isEmpty,
              fingerprint.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw AppError.usageUnavailable
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct HistoryRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var accountFingerprint: String
    var payload: HistorySnapshot

    var usageSnapshot: UsageSnapshot {
        payload.domainSnapshot
    }

    init(snapshot: UsageSnapshot) {
        schemaVersion = UsageHistoryStore.schemaVersion
        accountFingerprint = snapshot.accountFingerprint
        payload = HistorySnapshot(snapshot: snapshot)
    }
}

struct HistorySnapshot: Codable, Equatable, Sendable {
    var providerID: String
    var accountFingerprint: String
    var capturedAt: Date
    var cycleStart: Date?
    var cycleEnd: Date?
    var buckets: [HistoryBucket]
    var membershipType: String?
    var limitType: String?
    var totalPercentUsed: Double?

    init(snapshot: UsageSnapshot) {
        providerID = snapshot.providerID
        accountFingerprint = snapshot.accountFingerprint
        capturedAt = snapshot.capturedAt
        cycleStart = snapshot.cycleStart
        cycleEnd = snapshot.cycleEnd
        buckets = snapshot.buckets.map { HistoryBucket(id: $0.id, percentUsed: $0.percentUsed) }
        membershipType = snapshot.membershipType
        limitType = snapshot.limitType
        totalPercentUsed = snapshot.totalPercentUsed
    }

    var domainSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            accountFingerprint: accountFingerprint,
            capturedAt: capturedAt,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd,
            buckets: buckets.map {
                UsageBucket(id: $0.id, meter: .metered(percentUsed: $0.percentUsed, absolute: nil))
            },
            membershipType: membershipType,
            limitType: limitType,
            totalPercentUsed: totalPercentUsed
        )
    }
}

struct HistoryBucket: Codable, Equatable, Sendable {
    var id: UsagePoolID
    var percentUsed: Double
}

struct NoOpUsageHistory: UsageHistoryWriting {
    func record(_ snapshot: UsageSnapshot) async throws {}

    func snapshots(for fingerprint: String) async throws -> [UsageSnapshot] {
        []
    }
}
