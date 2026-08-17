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

    /// How long a caller waits on a read before carrying on without it. An
    /// approved read returns in milliseconds, so this budget only comes into
    /// play while the approval dialog is still on screen.
    private static let readBudget: Duration = .seconds(3)

    /// What a finished read found.
    private enum ReadOutcome: Sendable {
        case credentials(ClaudeCodeCredentials)
        case notSignedIn
        case refused(OSStatus)
        case failed(OSStatus)
    }

    private var cached: ClaudeCodeCredentials?
    private var nextAttemptAllowedAt: Date?
    private var readInProgress: Task<Void, Never>?

    func load() async -> ClaudeCodeCredentials? {
        if let cached, !cached.isExpired {
            return cached
        }

        if let nextAttemptAllowedAt, nextAttemptAllowedAt > Date() {
            return cached
        }

        startRead()
        await waitForRead()
        return cached
    }

    /// Starts the keychain read off the actor, at most one at a time.
    ///
    /// `SecItemCopyMatching` blocks inside the Security framework for as long as
    /// the approval dialog goes unanswered — which is indefinitely when the
    /// dialog is ignored or opens behind another window. Reading on the actor
    /// would wedge every later call to this repository, and with them the
    /// bootstrap awaiting them, leaving the app alive but permanently blank with
    /// no way back. Off the actor, an unanswered dialog costs one parked thread
    /// and nothing else.
    private func startRead() {
        guard readInProgress == nil else { return }

        readInProgress = Task.detached(priority: .utility) { [weak self] in
            let outcome = Self.read()
            await self?.absorb(outcome)
        }
    }

    /// Waits for an in-flight read, but never longer than `readBudget`.
    ///
    /// Giving up on the wait does not cancel the read: it stays parked, and
    /// whenever the dialog is finally answered the result still lands in the
    /// cache, so the next poll picks it up without prompting again.
    private func waitForRead() async {
        let deadline = ContinuousClock.now.advanced(by: Self.readBudget)

        while readInProgress != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func absorb(_ outcome: ReadOutcome) {
        readInProgress = nil

        switch outcome {
        case .credentials(let credentials):
            cached = credentials
            nextAttemptAllowedAt = nil
        case .notSignedIn:
            Self.logger.info("Claude Code is not signed in on this machine")
        case .refused(let status):
            // The user dismissed or denied the prompt. Backing off keeps the
            // dialog from reappearing on every refresh.
            Self.logger.error("Keychain access to Claude Code's credentials was refused (OSStatus \(status)); retrying in \(Int(Self.retryAfterRefusal / 60)) minutes")
            nextAttemptAllowedAt = Date().addingTimeInterval(Self.retryAfterRefusal)
        case .failed(let status):
            Self.logger.error("Claude Code keychain read failed (OSStatus \(status))")
        }
    }

    // MARK: - Off-actor reading

    /// Blocking. Only ever called from the detached task in `startRead()`.
    private static func read() -> ReadOutcome {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data, let credentials = decode(data) {
            return .credentials(credentials)
        }

        // Claude Code falls back to this file when the keychain is unavailable,
        // so it is worth trying whatever the keychain just said.
        if let credentials = readFile() {
            return .credentials(credentials)
        }

        switch status {
        case errSecItemNotFound:
            return .notSignedIn
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed, errSecInteractionRequired:
            return .refused(status)
        default:
            return .failed(status)
        }
    }

    private static func readFile() -> ClaudeCodeCredentials? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")

        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    private static func decode(_ data: Data) -> ClaudeCodeCredentials? {
        do {
            return try ClaudeCodeCredentials(json: data)
        } catch {
            logger.error("Failed to decode Claude Code credentials: \(error.localizedDescription)")
            return nil
        }
    }
}
