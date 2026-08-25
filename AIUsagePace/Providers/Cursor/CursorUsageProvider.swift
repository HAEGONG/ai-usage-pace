struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"

    var sessionLoader: any SessionLoading
    var apiClient: CursorAPIClient

    init(
        sessionLoader: any SessionLoading = CursorAuthReader(),
        apiClient: CursorAPIClient = CursorAPIClient()
    ) {
        self.sessionLoader = sessionLoader
        self.apiClient = apiClient
    }

    func loadFingerprint() async throws -> String {
        try await sessionLoader.loadSession().accountFingerprint
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let session = try await sessionLoader.loadSession()
        return try await apiClient.fetchSnapshot(session: session)
    }
}
