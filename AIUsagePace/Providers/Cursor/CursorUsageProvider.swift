struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"

    var apiClient: CursorAPIClient

    init(apiClient: CursorAPIClient = CursorAPIClient()) {
        self.apiClient = apiClient
    }

    func fetchUsage(session: CursorSession) async throws -> UsageSnapshot {
        return try await apiClient.fetchSnapshot(session: session)
    }
}
