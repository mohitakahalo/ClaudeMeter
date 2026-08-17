//
//  NetworkService.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation
import os

/// Actor-isolated network service using URLSession
actor NetworkService: NetworkServiceProtocol {
    private static let logger = Logger(subsystem: "com.claudemeter", category: "NetworkService")
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    /// Perform a generic HTTP request using a claude.ai session cookie
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod = .get,
        sessionKey: String
    ) async throws -> T {
        try await request(endpoint, method: method, authorization: .sessionCookie(sessionKey))
    }

    /// Perform a generic HTTP request with an explicit authorization scheme
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod = .get,
        authorization: APIAuthorization
    ) async throws -> T {
        // Validate HTTPS
        guard endpoint.hasPrefix("https://") else {
            throw NetworkError.invalidURL
        }

        guard let url = URL(string: endpoint) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch authorization {
        case .sessionCookie(let sessionKey):
            // Browser-like headers, since claude.ai fronts its web API with
            // Cloudflare bot protection. Origin must include the scheme —
            // a bare host is an invalid Origin header.
            request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
            request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Constants.API.oauthBeta, forHTTPHeaderField: "anthropic-beta")
            request.setValue("ClaudeMeter/\(Bundle.main.shortVersion)", forHTTPHeaderField: "User-Agent")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""

        // Handle HTTP status codes
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<unable to decode>"
            Self.logger.error("HTTP \(httpResponse.statusCode) from \(endpoint): \(responseBody.prefix(500))")

            // An HTML body on an API endpoint means a Cloudflare interstitial
            // rather than a real API error.
            if contentType.contains("text/html") {
                throw NetworkError.blockedByBotProtection
            }

            if httpResponse.statusCode == 429 {
                throw NetworkError.rateLimitExceeded
            }

            // Claude returns 401 for a missing credential but 403 with
            // `permission_error` / `account_session_invalid` for one that has
            // expired — both mean "re-authenticate", not "server problem".
            if httpResponse.statusCode == 401 {
                throw NetworkError.authenticationFailed
            }
            if httpResponse.statusCode == 403 {
                if Self.isAuthenticationFailure(data) {
                    throw NetworkError.authenticationFailed
                }
                throw NetworkError.accessForbidden
            }

            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        // A 200 carrying HTML is also a challenge page, not usage data.
        if contentType.contains("text/html") {
            Self.logger.error("Received HTML body from \(endpoint) — bot protection challenge")
            throw NetworkError.blockedByBotProtection
        }

        // Decode response
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "<unable to decode>"
            Self.logger.error("Failed to decode response from \(endpoint): \(error.localizedDescription)\nResponse: \(responseBody.prefix(500))")
            throw NetworkError.decodingFailed(underlyingError: error)
        }
    }

    /// Recognises Claude's typed error envelope for an expired credential:
    ///
    /// ```json
    /// {"type":"error","error":{"type":"permission_error",
    ///  "details":{"error_code":"account_session_invalid"}}}
    /// ```
    private static func isAuthenticationFailure(_ data: Data) -> Bool {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable {
                struct Details: Decodable {
                    let errorCode: String?

                    enum CodingKeys: String, CodingKey {
                        case errorCode = "error_code"
                    }
                }

                let type: String?
                let message: String?
                let details: Details?
            }

            let error: APIError?
        }

        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              let error = envelope.error else {
            return false
        }

        if let code = error.details?.errorCode,
           code.contains("session_invalid") || code.contains("authentication") || code.contains("unauthorized") {
            return true
        }

        if error.type == "authentication_error" {
            return true
        }

        if error.type == "permission_error",
           let message = error.message?.lowercased(),
           message.contains("authorization") || message.contains("authenticat") {
            return true
        }

        return false
    }
}

extension Bundle {
    /// Marketing version, for the User-Agent sent to Anthropic's API.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
