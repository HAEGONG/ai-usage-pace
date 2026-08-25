protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func loadSession() async throws -> ProviderSession
}

/// A single authenticated session read, carrying the account fingerprint and a
/// bound usage fetch. Reading auth once and reusing it for both the identity
/// check and the API request prevents mixing two accounts within one refresh
/// (e.g. if the user runs `grok login` or switches accounts mid-refresh).
struct ProviderSession: Sendable {
    let accountFingerprint: String
    private let fetch: @Sendable () async throws -> UsageSnapshot

    init(
        accountFingerprint: String,
        fetch: @escaping @Sendable () async throws -> UsageSnapshot
    ) {
        self.accountFingerprint = accountFingerprint
        self.fetch = fetch
    }

    func fetchUsage() async throws -> UsageSnapshot {
        try await fetch()
    }
}
