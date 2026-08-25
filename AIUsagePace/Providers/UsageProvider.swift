protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func loadFingerprint() async throws -> String
    func fetchUsage() async throws -> UsageSnapshot
}
