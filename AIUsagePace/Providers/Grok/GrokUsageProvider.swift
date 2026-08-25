struct GrokUsageProvider: UsageProvider {
    let id = "grok"
    let displayName = "Grok"

    var authReader: GrokAuthReader
    var apiClient: GrokAPIClient

    init(
        authReader: GrokAuthReader = GrokAuthReader(),
        apiClient: GrokAPIClient = GrokAPIClient()
    ) {
        self.authReader = authReader
        self.apiClient = apiClient
    }

    func loadFingerprint() async throws -> String {
        try await authReader.loadSession().accountFingerprint
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let session = try await authReader.loadSession()
        return try await apiClient.fetchSnapshot(session: session)
    }
}
