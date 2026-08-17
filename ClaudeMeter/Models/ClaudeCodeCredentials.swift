//
//  ClaudeCodeCredentials.swift
//  ClaudeMeter
//

import Foundation

/// OAuth credentials written by Claude Code, read from the login keychain.
///
/// ClaudeMeter only ever reads these. Refreshing would rotate the refresh
/// token and invalidate Claude Code's own copy, so an expired token is
/// reported rather than renewed — Claude Code refreshes it on its next run.
struct ClaudeCodeCredentials: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?

    /// Treated as expired slightly early so a fetch does not race the boundary.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 30
    }
}

extension ClaudeCodeCredentials {
    /// Decodes the `Claude Code-credentials` payload.
    ///
    /// ```json
    /// { "claudeAiOauth": { "accessToken": "...", "expiresAt": 1786967414729 } }
    /// ```
    /// `expiresAt` is milliseconds since the epoch.
    init(json data: Data) throws {
        struct Payload: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double?
                let subscriptionType: String?
            }
            let claudeAiOauth: OAuth?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let oauth = payload.claudeAiOauth, !oauth.accessToken.isEmpty else {
            throw KeychainError.notFound
        }

        self.init(
            accessToken: oauth.accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType
        )
    }
}
