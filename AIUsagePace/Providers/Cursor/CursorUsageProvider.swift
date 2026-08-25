struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"

    var sessionLoader: any SessionLoading
    var apiClient: CursorAPIClient
    var grokBotClient: GrokBotAPIClient

    init(
        sessionLoader: any SessionLoading = CursorAuthReader(),
        apiClient: CursorAPIClient = CursorAPIClient(),
        grokBotClient: GrokBotAPIClient = GrokBotAPIClient()
    ) {
        self.sessionLoader = sessionLoader
        self.apiClient = apiClient
        self.grokBotClient = grokBotClient
    }

    func loadSession() async throws -> ProviderSession {
        let session = try await sessionLoader.loadSession()
        let apiClient = apiClient
        let grokBotClient = grokBotClient
        return ProviderSession(accountFingerprint: session.accountFingerprint) {
            var snapshot = try await apiClient.fetchSnapshot(session: session)
            do {
                let status = try await grokBotClient.fetchStatus(session: session)
                if let bucket = try GrokBotUsageMapper.bucket(from: status) {
                    snapshot = snapshot.appending(bucket)
                }
            } catch let error as AppError {
                snapshot = snapshot.withPoolError(.grokBotWeekly, error)
            } catch {
                snapshot = snapshot.withPoolError(.grokBotWeekly, .networkFailure)
            }
            return snapshot
        }
    }
}
