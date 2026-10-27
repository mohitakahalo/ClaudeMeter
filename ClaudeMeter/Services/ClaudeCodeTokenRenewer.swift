//
//  ClaudeCodeTokenRenewer.swift
//  ClaudeMeter
//

import Foundation
import os

/// Protocol for getting Claude Code to renew its own OAuth token.
protocol ClaudeCodeTokenRenewerProtocol: Actor {
    /// Ask Claude Code to renew its token. Returns whether the CLI ran and
    /// exited cleanly — not that the token changed, which the caller checks by
    /// reading the keychain again.
    func renew() async -> Bool
}

/// Renews Claude Code's OAuth token by running its own CLI.
///
/// The access token lasts about eight hours, and only a running Claude Code
/// renews it, so a day without a session used to leave the meter dead. The
/// meter cannot renew the token itself: renewal rotates the refresh token, and
/// a rotation Claude Code does not know about signs it out. The CLI renews
/// under its own lock and writes the result back to the keychain, so letting
/// it do the work keeps both apps on the same token.
///
/// `claude -p /usage` is the cheapest command that renews: it is a local
/// slash command that reads the same usage endpoint the meter does, with
/// renewal enabled, and makes no model request — so it costs no quota and,
/// with `--no-session-persistence`, leaves no session behind.
actor ClaudeCodeTokenRenewer: ClaudeCodeTokenRenewerProtocol {
    private static let logger = Logger(subsystem: "com.claudemeter", category: "ClaudeCodeTokenRenewer")

    /// Minimum gap between runs. When renewal cannot succeed — signed out, or
    /// the refresh token itself expired — this keeps the meter from spawning
    /// the CLI on every poll.
    private static let minimumInterval: TimeInterval = 15 * 60

    /// The CLI answers in well under a second; anything near this is stuck.
    private static let timeout: Duration = .seconds(30)

    private static let arguments = ["-p", "/usage", "--no-session-persistence", "--output-format", "json"]

    private var lastAttemptAt: Date?

    func renew() async -> Bool {
        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < Self.minimumInterval {
            return false
        }
        lastAttemptAt = Date()

        guard let executable = Self.locateExecutable() else {
            Self.logger.info("Claude Code CLI not found; cannot renew its token")
            return false
        }

        let status = await Self.run(executable)
        if status == 0 {
            Self.logger.info("Claude Code renewed its token")
            return true
        }

        Self.logger.error("Claude Code token renewal exited with status \(status.map(String.init) ?? "nil", privacy: .public)")
        return false
    }

    /// Apps launched from Finder get a minimal PATH, so look where the
    /// installers put the CLI rather than relying on the shell.
    private static func locateExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs the CLI and returns its exit status, or nil if it could not be
    /// started or was killed for running past `timeout`.
    private static func run(_ executable: URL) async -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Outside any project, so no project settings or hooks come into play.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let timedOut = finished.terminationReason == .uncaughtSignal
                continuation.resume(returning: timedOut ? nil : finished.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                logger.error("Could not launch Claude Code: \(error.localizedDescription, privacy: .public)")
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }

            Task.detached {
                try? await Task.sleep(for: timeout)
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
