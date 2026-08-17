//
//  NetworkServiceProtocol.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// HTTP methods supported by the network service
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

/// How a request authenticates.
enum APIAuthorization: Sendable, Equatable {
    /// claude.ai web API: `Cookie: sessionKey=…`
    case sessionCookie(String)
    /// Anthropic OAuth API: `Authorization: Bearer …`
    case bearer(String)
}

/// Protocol for network operations
protocol NetworkServiceProtocol: Actor {
    /// Perform a generic HTTP request
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod,
        sessionKey: String
    ) async throws -> T

    /// Perform a generic HTTP request with an explicit authorization scheme
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod,
        authorization: APIAuthorization
    ) async throws -> T
}

extension NetworkServiceProtocol {
    /// Default routing so existing cookie-only implementations (and test
    /// doubles) keep working without adopting the new entry point.
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod,
        authorization: APIAuthorization
    ) async throws -> T {
        switch authorization {
        case .sessionCookie(let key):
            return try await request(endpoint, method: method, sessionKey: key)
        case .bearer:
            throw NetworkError.invalidResponse
        }
    }
}
