//
//  ClaudeCodeTokenRenewerStub.swift
//  ClaudeMeterTests
//

import Foundation
@testable import ClaudeMeter

/// Stands in for the real renewer so tests never launch the Claude Code CLI.
actor ClaudeCodeTokenRenewerStub: ClaudeCodeTokenRenewerProtocol {
    private let onRenew: @Sendable () async -> Bool
    private(set) var renewCount = 0

    /// Defaults to a renewal that fails, as when the CLI is not installed.
    init(onRenew: @escaping @Sendable () async -> Bool = { false }) {
        self.onRenew = onRenew
    }

    func renew() async -> Bool {
        renewCount += 1
        return await onRenew()
    }
}
