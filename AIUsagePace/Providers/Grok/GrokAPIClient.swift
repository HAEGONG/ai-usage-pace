import Foundation

struct GrokAPIClient: Sendable {
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    var http: any HTTPClient

    init(http: any HTTPClient = AllowlistedHTTPClient()) {
        self.http = http
    }

    func fetchSnapshot(session: GrokSession, now: Date = Date()) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.billingURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            throw AppError.authenticationExpired
        case 204:
            throw AppError.usageUnavailable
        default:
            throw AppError.networkFailure
        }

        let decoder = JSONDecoder()
        let billing: GrokBillingResponse
        do {
            billing = try decoder.decode(GrokBillingResponse.self, from: data)
        } catch {
            throw AppError.unsupportedResponseSchema
        }

        return try GrokUsageMapper.snapshot(from: billing, session: session, capturedAt: now)
    }
}
