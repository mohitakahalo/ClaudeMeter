//
//  ClaudeCodeCredentialsRepository.swift
//  ClaudeMeter
//

import Foundation
import os
import Security

/// Protocol for reading Claude Code's OAuth credentials.
protocol ClaudeCodeCredentialsRepositoryProtocol: Actor {
    /// Load the current credentials, or nil when Claude Code is not signed in.
    func load() async -> ClaudeCodeCredentials?
}

/// Reads the OAuth credentials Claude Code stores in the login keychain.
///
/// The item belongs to Claude Code, so the first read prompts for keychain
/// access; "Always Allow" makes later reads silent. Credentials are held until
/// they expire rather than re-read every poll, because someone who answered
/// "Allow" (not "Always Allow"), or who denied the prompt, would otherwise face
/// a dialog every refresh interval.
///
/// Reads only. Refreshing would rotate the refresh token and invalidate Claude
/// Code's own copy.
actor ClaudeCodeCredentialsRepository: ClaudeCodeCredentialsRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.claudemeter", category: "ClaudeCodeCredentials")
    private static let serviceName = "Claude Code-credentials"

    /// How long to wait before asking again after the keychain refuses.
    private static let retryAfterRefusal: TimeInterval = 15 * 60

    private var cached: ClaudeCodeCredentials?
    private var nextAttemptAllowedAt: Date?

    func load() async -> ClaudeCodeCredentials? {
        if let cached, !cached.isExpired {
            return cached
        }

        if let nextAttemptAllowedAt, nextAttemptAllowedAt > Date() {
            return cached
        }

        if let credentials = loadFromKeychain() ?? loadFromFile() {
            cached = credentials
            nextAttemptAllowedAt = nil
            return credentials
        }

        return cached
    }

    private func loadFromKeychain() -> ClaudeCodeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            switch status {
            case errSecItemNotFound:
                Self.logger.info("Claude Code is not signed in on this machine")
            case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed, errSecInteractionRequired:
                // The user dismissed or denied the prompt. Backing off keeps the
                // dialog from reappearing on every refresh.
                Self.logger.error("Keychain access to Claude Code's credentials was refused (OSStatus \(status)); retrying in \(Int(Self.retryAfterRefusal / 60)) minutes")
                nextAttemptAllowedAt = Date().addingTimeInterval(Self.retryAfterRefusal)
            default:
                Self.logger.error("Claude Code keychain read failed (OSStatus \(status))")
            }
            return nil
        }

        return decode(data)
    }

    private func loadFromFile() -> ClaudeCodeCredentials? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")

        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    private func decode(_ data: Data) -> ClaudeCodeCredentials? {
        do {
            return try ClaudeCodeCredentials(json: data)
        } catch {
            Self.logger.error("Failed to decode Claude Code credentials: \(error.localizedDescription)")
            return nil
        }
    }
}
