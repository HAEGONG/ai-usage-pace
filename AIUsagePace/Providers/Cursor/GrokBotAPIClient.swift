import Foundation

struct GrokBotAPIClient: Sendable {
    static let sandUsageStatusURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!

    var http: any HTTPClient

    init(http: any HTTPClient = AllowlistedHTTPClient()) {
        self.http = http
    }

    func fetchStatus(session: CursorSession) async throws -> GrokBotUsageStatusResponse {
        var request = URLRequest(url: Self.sandUsageStatusURL)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let cookie = try CursorAuthReader.cookieValue(userID: session.userID, accessToken: session.accessToken)
        request.setValue("WorkosCursorSessionToken=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

        do {
            return try JSONDecoder().decode(GrokBotUsageStatusResponse.self, from: data)
        } catch {
            throw AppError.unsupportedResponseSchema
        }
    }
}
