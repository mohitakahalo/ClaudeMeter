//
//  ClaudeCodeCredentialsRepositoryStub.swift
//  ClaudeMeterTests
//

import Foundation
@testable import ClaudeMeter

/// Stands in for the real repository so tests never read the login keychain —
/// otherwise every result depends on whether Claude Code happens to be signed
/// in on the machine running them.
actor ClaudeCodeCredentialsRepositoryStub: ClaudeCodeCredentialsRepositoryProtocol {
    private var credentials: ClaudeCodeCredentials?
    private(set) var loadCount = 0
    private(set) var invalidated: [ClaudeCodeCredentials] = []

    /// Defaults to "Claude Code is not signed in", which keeps the browser
    /// session path under test.
    init(credentials: ClaudeCodeCredentials? = nil) {
        self.credentials = credentials
    }

    func load() async -> ClaudeCodeCredentials? {
        loadCount += 1
        return credentials
    }

    /// What Claude Code would leave in the keychain after renewing.
    func replace(with credentials: ClaudeCodeCredentials?) {
        self.credentials = credentials
    }

    func invalidate(_ rejected: ClaudeCodeCredentials) async {
        invalidated.append(rejected)
    }
}
