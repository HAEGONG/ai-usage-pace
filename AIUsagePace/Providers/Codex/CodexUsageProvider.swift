struct CodexUsageProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"

    var authReader: CodexAuthReader
    var apiClient: CodexAPIClient

    init(
        authReader: CodexAuthReader = CodexAuthReader(),
        apiClient: CodexAPIClient = CodexAPIClient()
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
