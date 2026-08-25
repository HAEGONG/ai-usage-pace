protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func fetchUsage(session: CursorSession) async throws -> UsageSnapshot
}
