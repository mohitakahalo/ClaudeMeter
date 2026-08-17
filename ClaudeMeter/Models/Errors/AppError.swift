//
//  AppError.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// Application-level errors with user-facing messages
enum AppError: LocalizedError {
    case noSessionKey
    case networkError(NetworkError)
    case keychainError(KeychainError)
    case sessionKeyInvalid
    case apiResponseInvalid
    case organizationNotFound
    case cacheCorrupted
    case claudeCodeTokenExpired

    var errorDescription: String? {
        switch self {
        case .noSessionKey:
            return "No session key found. Please complete setup."
        case .networkError(let error):
            return error.localizedDescription
        case .keychainError(let error):
            return error.localizedDescription
        case .sessionKeyInvalid:
            return "Session key is invalid or expired. Please update in settings."
        case .apiResponseInvalid:
            return "Unable to parse usage data from server."
        case .organizationNotFound:
            return "No organizations found for this account."
        case .cacheCorrupted:
            return "Cached data is corrupted. Fetching fresh data..."
        case .claudeCodeTokenExpired:
            return "Claude Code's session has expired. Run Claude Code to refresh it, or import a browser session."
        }
    }

    /// Whether error is recoverable without user action
    var isRecoverable: Bool {
        switch self {
        case .networkError, .cacheCorrupted, .apiResponseInvalid, .claudeCodeTokenExpired:
            return true
        case .noSessionKey, .sessionKeyInvalid, .organizationNotFound, .keychainError:
            return false
        }
    }

    /// User action to resolve error
    var recoveryAction: String? {
        switch self {
        case .noSessionKey:
            return "Complete Setup"
        case .sessionKeyInvalid:
            return "Update Session Key"
        case .networkError:
            return "Retry"
        case .organizationNotFound:
            return "Check Account"
        case .claudeCodeTokenExpired:
            return "Import Browser Session"
        default:
            return nil
        }
    }
}
