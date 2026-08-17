//
//  UsageDataSource.swift
//  ClaudeMeter
//

import Foundation

/// Where the currently displayed usage data came from.
enum UsageDataSource: String, Codable, Sendable {
    /// Anthropic's OAuth usage endpoint, via Claude Code's keychain token
    case claudeCode
    /// claude.ai web API, via an imported browser session cookie
    case browserSession

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code session"
        case .browserSession:
            return "Browser session"
        }
    }
}
