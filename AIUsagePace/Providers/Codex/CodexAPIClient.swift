import Foundation

struct CodexAPIClient: Sendable {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    var http: any HTTPClient

    init(http: any HTTPClient = AllowlistedHTTPClient()) {
        self.http = http
    }

    func fetchSnapshot(session: CodexSession, now: Date = Date()) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = session.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

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

        let usage: CodexUsageResponse
        do {
            usage = try CodexUsageDecoding.makeDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw AppError.unsupportedResponseSchema
        }

        return try CodexUsageMapper.snapshot(from: usage, session: session, capturedAt: now)
    }
}
