//
//  KeychainRepository.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation
import Security

/// Actor-isolated repository for secure Keychain operations
actor KeychainRepository: KeychainRepositoryProtocol {
    private static let serviceName = "com.claudemeter.sessionkey"
    private static let accessGroup = "$(AppIdentifierPrefix)com.claudemeter"

    /// How long to wait on a Security call before giving up on it this round.
    ///
    /// A `SecItem*` call blocks until the system's approval dialog is answered,
    /// and a build the stored item's ACL does not yet trust puts that dialog on
    /// screen. Waiting forever wedges the caller — bootstrap awaits these — so a
    /// round that outlasts the budget is reported as unavailable and retried on
    /// the next poll rather than freezing the app behind a dialog.
    private static let timeout: Duration = .seconds(10)

    /// Save session key to Keychain with security attributes
    func save(sessionKey: String, account: String) async throws {
        guard let data = sessionKey.data(using: .utf8) else {
            throw KeychainError.saveFailed(OSStatus: errSecParam)
        }

        let status = await Self.perform {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: Self.serviceName,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
                kSecAttrAccessGroup as String: Self.accessGroup,
            ]

            return SecItemAdd(query as CFDictionary, nil)
        }

        guard let status else {
            throw KeychainError.saveFailed(OSStatus: errSecInteractionRequired)
        }

        if status == errSecDuplicateItem {
            // Item already exists, update it instead
            try await update(sessionKey: sessionKey, account: account)
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(OSStatus: status)
        }
    }

    /// Retrieve session key from Keychain
    func retrieve(account: String) async throws -> String {
        let result = await Self.perform { () -> (status: OSStatus, data: Data?) in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: Self.serviceName,
                kSecReturnData as String: kCFBooleanTrue as Any,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrAccessGroup as String: Self.accessGroup,
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return (status, item as? Data)
        }

        guard let result,
              result.status == errSecSuccess,
              let data = result.data,
              let sessionKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }

        return sessionKey
    }

    /// Update existing session key in Keychain
    func update(sessionKey: String, account: String) async throws {
        guard let data = sessionKey.data(using: .utf8) else {
            throw KeychainError.updateFailed(OSStatus: errSecParam)
        }

        let status = await Self.perform {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: Self.serviceName,
                kSecAttrAccessGroup as String: Self.accessGroup,
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]

            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }

        guard let status, status == errSecSuccess else {
            throw KeychainError.updateFailed(OSStatus: status ?? errSecInteractionRequired)
        }
    }

    /// Delete session key from Keychain
    func delete(account: String) async throws {
        let status = await Self.perform {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: Self.serviceName,
                kSecAttrAccessGroup as String: Self.accessGroup,
            ]

            return SecItemDelete(query as CFDictionary)
        }

        guard let status else {
            throw KeychainError.deleteFailed(OSStatus: errSecInteractionRequired)
        }

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(OSStatus: status)
        }
    }

    /// Check if session key exists for account
    func exists(account: String) async -> Bool {
        let status = await Self.perform {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: Self.serviceName,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrAccessGroup as String: Self.accessGroup,
            ]

            return SecItemCopyMatching(query as CFDictionary, nil)
        }

        return status == errSecSuccess
    }

    // MARK: - Off-actor execution

    /// Runs a blocking Security call off the actor.
    ///
    /// Returns nil when the call outlasts `timeout`. Giving up on the wait does
    /// not cancel the call — it stays parked on its own thread until the dialog
    /// is answered — but the actor stays free, so an unanswered prompt costs one
    /// background thread instead of the entire app.
    private static func perform<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) async -> Value? {
        let box = ResultBox<Value>()

        Task.detached(priority: .userInitiated) {
            box.store(work())
        }

        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            if let value = box.value {
                return value
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        return nil
    }
}

/// Carries a background call's result back to the actor waiting on it.
private final class ResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    func store(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        stored = value
    }

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
