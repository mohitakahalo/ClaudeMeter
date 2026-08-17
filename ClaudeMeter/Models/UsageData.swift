//
//  UsageData.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// Complete usage data across all limit types
struct UsageData: Codable, Equatable, Sendable {
    /// 5-hour rolling session usage
    let sessionUsage: UsageLimit

    /// 7-day weekly usage across all models, when the account has such a limit.
    ///
    /// Not every plan is metered on a 7-day window, and for those the API omits
    /// the entry entirely. A synthesised zero would render as a healthy, empty
    /// week rather than "not applicable", so absence is carried as absence.
    let weeklyUsage: UsageLimit?

    /// 7-day limits scoped to a specific model, in the order the API reported them
    let scopedUsage: [ScopedUsageLimit]

    /// Extra-usage credits, for accounts that have them enabled
    let spendUsage: SpendUsage?

    /// Timestamp of when this data was fetched
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case sessionUsage = "session_usage"
        case weeklyUsage = "weekly_usage"
        case scopedUsage = "scoped_usage"
        case spendUsage = "spend_usage"
        case lastUpdated = "last_updated"
    }

    /// Read-only: caches written before scoped limits existed carry a single Sonnet entry.
    /// Kept out of `CodingKeys` so `encode` stays synthesized.
    private enum LegacyCodingKeys: String, CodingKey {
        case sonnetUsage = "sonnet_usage"
    }
}

extension UsageData {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sessionUsage = try container.decode(UsageLimit.self, forKey: .sessionUsage)
        weeklyUsage = try container.decodeIfPresent(UsageLimit.self, forKey: .weeklyUsage)
        spendUsage = try container.decodeIfPresent(SpendUsage.self, forKey: .spendUsage)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)

        if let scoped = try container.decodeIfPresent([ScopedUsageLimit].self, forKey: .scopedUsage) {
            scopedUsage = scoped
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            scopedUsage = try legacy.decodeIfPresent(UsageLimit.self, forKey: .sonnetUsage)
                .map { [ScopedUsageLimit(name: "Sonnet", limit: $0, isActive: false)] } ?? []
        }
    }
}

extension UsageData {
    /// Returns the primary usage level for menu bar display
    var primaryStatus: UsageStatus {
        sessionUsage.status
    }

    /// Human-readable staleness indicator
    var freshnessDescription: String {
        let elapsed = Date().timeIntervalSince(lastUpdated)
        if elapsed < 60 {
            return "just now"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60)) minutes ago"
        } else {
            return "\(Int(elapsed / 3600)) hours ago"
        }
    }

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > Constants.Refresh.stalenessThreshold
    }

    /// Off-pace signal for the menu bar badge.
    /// Hot when either window burns faster than sustainable (highest ratio wins,
    /// since an imminent lockout matters more than long-term underuse). Cold only
    /// when the weekly window is underused - idle time within the short session
    /// window is not a meaningful underuse signal.
    /// - Parameter weeklyPaceDays: Days per week the weekly quota is expected to
    ///   be consumed over (5-7); sustainable weekly pace is measured against this.
    func paceSignal(weeklyPaceDays: Int) -> PaceSignal? {
        let weeklyPacing = Constants.Pacing.weeklyPacingDuration(days: weeklyPaceDays)
        let sessionRatio = sessionUsage.paceRatio(windowDuration: Constants.Pacing.sessionWindow)
        let weeklyRatio = weeklyUsage?.paceRatio(
            windowDuration: Constants.Pacing.weeklyWindow,
            pacingDuration: weeklyPacing
        )

        var hotSignals: [PaceSignal] = []
        if let sessionRatio, sessionRatio > Constants.Pacing.riskThreshold {
            hotSignals.append(makeSignal(
                .hot, limit: sessionUsage, ratio: sessionRatio, windowName: "5-hour",
                windowDuration: Constants.Pacing.sessionWindow
            ))
        }
        if let weeklyUsage, let weeklyRatio, weeklyRatio > Constants.Pacing.riskThreshold {
            hotSignals.append(makeSignal(
                .hot, limit: weeklyUsage, ratio: weeklyRatio, windowName: "7-day",
                windowDuration: Constants.Pacing.weeklyWindow, pacingDuration: weeklyPacing, paceDays: weeklyPaceDays
            ))
        }
        if let hottest = hotSignals.max(by: { $0.ratio < $1.ratio }) {
            return hottest
        }

        if let weeklyUsage, let weeklyRatio, weeklyRatio < Constants.Pacing.underuseThreshold {
            return makeSignal(
                .cold, limit: weeklyUsage, ratio: weeklyRatio, windowName: "7-day",
                windowDuration: Constants.Pacing.weeklyWindow, pacingDuration: weeklyPacing, paceDays: weeklyPaceDays
            )
        }

        return nil
    }

    /// Ratio to lead the menu bar with in pace-first mode when no off-pace
    /// signal fires: the higher — "worst", i.e. closest to or furthest past a
    /// sustainable pace — of the session and weekly ratios, so an on-pace weekly
    /// isn't hidden behind an idle session. `nil` when neither window has a
    /// ratio yet (both inside the grace period / post-reset).
    func fallbackPaceRatio(weeklyPaceDays: Int) -> Double? {
        let sessionRatio = sessionUsage.paceRatio(windowDuration: Constants.Pacing.sessionWindow)
        let weeklyRatio = weeklyUsage?.paceRatio(
            windowDuration: Constants.Pacing.weeklyWindow,
            pacingDuration: Constants.Pacing.weeklyPacingDuration(days: weeklyPaceDays)
        )
        return [sessionRatio, weeklyRatio].compactMap { $0 }.max()
    }

    private func makeSignal(
        _ kind: PaceKind,
        limit: UsageLimit,
        ratio: Double,
        windowName: String,
        windowDuration: TimeInterval,
        pacingDuration: TimeInterval? = nil,
        paceDays: Int? = nil
    ) -> PaceSignal {
        PaceSignal(
            kind: kind,
            ratio: ratio,
            windowName: windowName,
            usedPercent: limit.utilization,
            expectedPercent: limit.expectedUsagePercent(windowDuration: windowDuration, pacingDuration: pacingDuration) ?? 0,
            paceDays: paceDays
        )
    }
}
