import Foundation

struct CursorAPIClient: Sendable {
    static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    var http: any HTTPClient

    init(http: any HTTPClient = AllowlistedHTTPClient()) {
        self.http = http
    }

    func fetchSnapshot(session: CursorSession, now: Date = Date()) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageSummaryURL)
        request.httpMethod = "GET"
        let cookie = try CursorAuthReader.cookieValue(userID: session.userID, accessToken: session.accessToken)
        request.setValue("WorkosCursorSessionToken=\(cookie)", forHTTPHeaderField: "Cookie")

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
        let summary: CursorUsageSummaryResponse
        do {
            summary = try decoder.decode(CursorUsageSummaryResponse.self, from: data)
        } catch {
            throw AppError.unsupportedResponseSchema
        }

        return try CursorUsageMapper.snapshot(from: summary, session: session, capturedAt: now)
    }
}
