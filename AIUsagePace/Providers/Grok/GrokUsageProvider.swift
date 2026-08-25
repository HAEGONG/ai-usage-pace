struct GrokUsageProvider: UsageProvider {
    let id = "grok"
    let displayName = "Grok CLI"

    var authReader: GrokAuthReader
    var apiClient: GrokAPIClient

    init(
        authReader: GrokAuthReader = GrokAuthReader(),
        apiClient: GrokAPIClient = GrokAPIClient()
    ) {
        self.authReader = authReader
        self.apiClient = apiClient
    }

    func loadSession() async throws -> ProviderSession {
        let session = try await authReader.loadSession()
        let apiClient = apiClient
        return ProviderSession(accountFingerprint: session.accountFingerprint) {
            try await apiClient.fetchSnapshot(session: session)
        }
    }
}
