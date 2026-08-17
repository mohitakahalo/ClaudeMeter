//
//  UsageService.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation
import os

/// Actor-isolated usage service with retry logic.
///
/// Usage can be read two ways. Claude Code's OAuth token is preferred: it is
/// already on the machine, it is refreshed by Claude Code itself, and
/// `api.anthropic.com` is not behind the bot protection that fronts the web
/// app. An imported claude.ai browser cookie is the fallback, for people who
/// do not use Claude Code — those cookies expire every few days, which is what
/// leaves the meter frozen on stale numbers.
actor UsageService: UsageServiceProtocol {
    private static let logger = Logger(subsystem: "com.claudemeter", category: "UsageService")
    private let networkService: NetworkServiceProtocol
    private let cacheRepository: CacheRepositoryProtocol
    private let keychainRepository: KeychainRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let credentialsRepository: ClaudeCodeCredentialsRepositoryProtocol

    private let maxRetries = Constants.Network.maxRetries
    private let baseURL = Constants.API.claudeWebBase

    /// Source that last returned data, for display in settings.
    private var lastSuccessfulSource: UsageDataSource?

    init(
        networkService: NetworkServiceProtocol,
        cacheRepository: CacheRepositoryProtocol,
        keychainRepository: KeychainRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol,
        credentialsRepository: ClaudeCodeCredentialsRepositoryProtocol = ClaudeCodeCredentialsRepository()
    ) {
        self.networkService = networkService
        self.cacheRepository = cacheRepository
        self.keychainRepository = keychainRepository
        self.settingsRepository = settingsRepository
        self.credentialsRepository = credentialsRepository
    }

    /// Fetch usage data with cache integration and exponential backoff retry
    func fetchUsage(forceRefresh: Bool = false) async throws -> UsageData {
        // Clear cache if force refresh is requested
        if forceRefresh {
            await cacheRepository.invalidate()
        }

        // Check cache first (will be empty if force refresh)
        if let cachedData = await cacheRepository.get() {
            return cachedData
        }

        var oauthError: Error?

        if let credentials = await credentialsRepository.load() {
            if credentials.isExpired {
                Self.logger.warning("Claude Code token expired; falling back to browser session")
                oauthError = AppError.claudeCodeTokenExpired
            } else {
                do {
                    let usageData = try await fetchUsageWithOAuth(credentials)
                    lastSuccessfulSource = .claudeCode
                    await cacheRepository.set(usageData)
                    return usageData
                } catch {
                    Self.logger.error("OAuth usage fetch failed: \(error.localizedDescription)")
                    oauthError = error
                }
            }
        }

        do {
            let usageData = try await fetchUsageWithBrowserSession()
            lastSuccessfulSource = .browserSession
            return usageData
        } catch AppError.noSessionKey {
            // No browser cookie configured: the OAuth failure is the real story.
            throw oauthError ?? AppError.noSessionKey
        }
    }

    /// Whether usage can be read without the user importing a browser session.
    func isAutomaticAuthAvailable() async -> Bool {
        guard let credentials = await credentialsRepository.load() else { return false }
        return !credentials.isExpired
    }

    /// Source that last returned data successfully.
    func activeSource() async -> UsageDataSource? {
        lastSuccessfulSource
    }

    // MARK: - Claude Code (OAuth)

    private func fetchUsageWithOAuth(_ credentials: ClaudeCodeCredentials) async throws -> UsageData {
        let response: UsageAPIResponse = try await networkService.request(
            Constants.API.oauthUsage,
            method: .get,
            authorization: .bearer(credentials.accessToken)
        )

        return try response.toDomain()
    }

    // MARK: - Browser session (claude.ai)

    private func fetchUsageWithBrowserSession() async throws -> UsageData {
        let sessionKeyString: String
        do {
            sessionKeyString = try await keychainRepository.retrieve(account: "default")
        } catch KeychainError.notFound {
            throw AppError.noSessionKey
        } catch let error as KeychainError {
            throw AppError.keychainError(error)
        }

        let sessionKey = try SessionKey(sessionKeyString)

        // Get organization ID
        let settings = await settingsRepository.load()
        let organizationId: UUID

        if let cachedOrgId = settings.cachedOrganizationId {
            organizationId = cachedOrgId
        } else if let orgId = sessionKey.organizationId {
            organizationId = orgId
        } else {
            // Fetch organizations to get ID
            let orgs = try await fetchOrganizations()
            guard let firstOrg = orgs.first,
                  let uuid = firstOrg.organizationUUID else {
                throw AppError.organizationNotFound
            }
            organizationId = uuid
        }

        // Fetch usage data with retry logic
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let response: UsageAPIResponse = try await networkService.request(
                    "\(baseURL)/organizations/\(organizationId)/usage",
                    method: .get,
                    sessionKey: sessionKey.value
                )

                let usageData = try response.toDomain()

                // Cache the result
                await cacheRepository.set(usageData)

                return usageData

            } catch NetworkError.networkUnavailable {
                Self.logger.warning("Network unavailable (attempt \(attempt + 1)/\(self.maxRetries))")
                lastError = NetworkError.networkUnavailable
                let delay = pow(Constants.Network.backoffBase, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch NetworkError.rateLimitExceeded {
                // Rate limit hit - use longer exponential backoff
                Self.logger.warning("Rate limit exceeded (attempt \(attempt + 1)/\(self.maxRetries))")
                lastError = NetworkError.rateLimitExceeded
                let delay = pow(Constants.Network.rateLimitBackoffBase, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch NetworkError.blockedByBotProtection {
                // Cloudflare interstitial - transient, and never a reason to
                // tell the user their session expired.
                Self.logger.warning("Blocked by bot protection (attempt \(attempt + 1)/\(self.maxRetries))")
                lastError = NetworkError.blockedByBotProtection
                let delay = pow(Constants.Network.rateLimitBackoffBase, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch NetworkError.authenticationFailed {
                Self.logger.error("Authentication failed - session key invalid")
                throw AppError.sessionKeyInvalid
            } catch let error as URLError where error.code == .timedOut ||
                                               error.code == .cannotConnectToHost ||
                                               error.code == .networkConnectionLost ||
                                               error.code == .notConnectedToInternet {
                // Retry on timeout and connection errors
                Self.logger.warning("URL error: \(error.localizedDescription) (attempt \(attempt + 1)/\(self.maxRetries))")
                lastError = error
                let delay = pow(Constants.Network.backoffBase, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch {
                Self.logger.error("API request failed: \(error.localizedDescription)")
                throw AppError.networkError(error as? NetworkError ?? .invalidResponse)
            }
        }

        // If all retries failed, check for last known data
        if let lastKnown = await cacheRepository.getLastKnown() {
            Self.logger.warning("All retries failed, using cached data")
            return lastKnown
        }

        Self.logger.error("All retries failed, no cached data available")
        throw AppError.networkError(lastError as? NetworkError ?? .networkUnavailable)
    }

    /// Fetch list of organizations for the user
    func fetchOrganizations() async throws -> [Organization] {
        let sessionKeyString: String
        do {
            sessionKeyString = try await keychainRepository.retrieve(account: "default")
        } catch KeychainError.notFound {
            throw AppError.noSessionKey
        } catch let error as KeychainError {
            throw AppError.keychainError(error)
        }

        let sessionKey = try SessionKey(sessionKeyString)
        return try await fetchOrganizations(sessionKey: sessionKey)
    }

    /// Fetch list of organizations with explicit session key (for setup before keychain save)
    func fetchOrganizations(sessionKey: SessionKey) async throws -> [Organization] {
        let organizations: OrganizationListResponse = try await networkService.request(
            "\(baseURL)/organizations",
            method: .get,
            sessionKey: sessionKey.value
        )

        return organizations
    }

    /// Validate session key with Claude API
    func validateSessionKey(_ sessionKey: SessionKey) async throws -> Bool {
        do {
            let _: OrganizationListResponse = try await networkService.request(
                "\(baseURL)/organizations",
                method: .get,
                sessionKey: sessionKey.value
            )
            return true
        } catch NetworkError.authenticationFailed {
            return false
        } catch {
            throw error
        }
    }
}
