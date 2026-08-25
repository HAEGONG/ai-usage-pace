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

    func loadSession() async throws -> ProviderSession {
        let session = try await sessionLoader.loadSession()
        let apiClient = apiClient
        return ProviderSession(accountFingerprint: session.accountFingerprint) {
            try await apiClient.fetchSnapshot(session: session)
        }
    }
}
