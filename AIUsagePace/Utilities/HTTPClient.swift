import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct AllowlistedHTTPClient: HTTPClient {
    static let allowedHosts: Set<String> = [
        "cursor.com",
        "www.cursor.com",
        "api2.cursor.sh",
    ]

    private let session: URLSession
    private let redirectGuard: RedirectHostGuard

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never

        let redirectGuard = RedirectHostGuard(allowedHosts: Self.allowedHosts)
        self.redirectGuard = redirectGuard
        session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Self.validate(url: request.url)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkFailure
        }
        return (data, httpResponse)
    }

    static func validate(url: URL?) throws {
        guard let url, let host = url.host, url.scheme == "https" else {
            throw AppError.networkFailure
        }
        guard allowedHosts.contains(host) else {
            throw AppError.networkFailure
        }
    }
}

final class RedirectHostGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>

    init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.acceptedRedirect(from: request, allowedHosts: allowedHosts))
    }

    static func acceptedRedirect(from request: URLRequest, allowedHosts: Set<String>) -> URLRequest? {
        guard let url = request.url, let host = url.host, url.scheme == "https", allowedHosts.contains(host) else {
            return nil
        }
        return request
    }
}
