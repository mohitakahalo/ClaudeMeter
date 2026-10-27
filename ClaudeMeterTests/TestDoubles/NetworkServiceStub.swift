//
//  NetworkServiceStub.swift
//  ClaudeMeterTests
//
//  Created by Edd on 2026-01-09.
//

import Foundation
@testable import ClaudeMeter

actor NetworkServiceStub: NetworkServiceProtocol {
    private let responseData: Data
    private let error: Error?
    private(set) var requestCount: Int = 0
    private(set) var lastEndpoint: String?
    private(set) var bearerTokens: [String] = []
    private let rejectedBearerTokens: Set<String>

    init(responseData: Data, error: Error? = nil, rejectedBearerTokens: Set<String> = []) {
        self.responseData = responseData
        self.error = error
        self.rejectedBearerTokens = rejectedBearerTokens
    }

    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod,
        authorization: APIAuthorization
    ) async throws -> T {
        switch authorization {
        case .sessionCookie(let key):
            return try await request(endpoint, method: method, sessionKey: key)
        case .bearer(let token):
            bearerTokens.append(token)
            if rejectedBearerTokens.contains(token) {
                requestCount += 1
                lastEndpoint = endpoint
                throw NetworkError.authenticationFailed
            }
            return try await request(endpoint, method: method, sessionKey: token)
        }
    }

    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod,
        sessionKey: String
    ) async throws -> T {
        requestCount += 1
        lastEndpoint = endpoint

        if let error {
            throw error
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: responseData)
    }
}
