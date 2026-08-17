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
/// The item is owned by Claude Code, so the first read prompts for keychain
/// access; choosing "Always Allow" makes subsequent refreshes silent. Falls
/// back to `~/.claude/.credentials.json`, which Claude Code writes when the
/// keychain is unavailable.
actor ClaudeCodeCredentialsRepository: ClaudeCodeCredentialsRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.claudemeter", category: "ClaudeCodeCredentials")
    private static let serviceName = "Claude Code-credentials"

    func load() async -> ClaudeCodeCredentials? {
        if let credentials = loadFromKeychain() {
            return credentials
        }
        return loadFromFile()
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
            if status != errSecItemNotFound {
                Self.logger.debug("Claude Code keychain read failed (OSStatus \(status))")
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
