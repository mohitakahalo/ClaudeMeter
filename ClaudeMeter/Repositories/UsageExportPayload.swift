//
//  UsageExportPayload.swift
//  ClaudeMeter
//

import Foundation

/// The public `~/.claudemeter/usage.json` contract. Separate from `UsageData` so the
/// domain model and disk cache can change shape without breaking external scripts.
struct UsageExportPayload: Encodable {
    let sessionUsage: UsageLimit

    /// Null for accounts with no 7-day limit; the key stays present so existing
    /// scripts keep finding it.
    let weeklyUsage: UsageLimit?

    let scopedUsage: [ScopedUsageLimit]

    /// Extra-usage credits; null for accounts without them.
    let spendUsage: SpendUsage?

    /// Deprecated alias for `scopedUsage`, kept so existing statusline scripts keep working.
    let sonnetUsage: UsageLimit?

    let lastUpdated: Date

    init(_ data: UsageData) {
        sessionUsage = data.sessionUsage
        weeklyUsage = data.weeklyUsage
        scopedUsage = data.scopedUsage
        spendUsage = data.spendUsage
        sonnetUsage = data.scopedUsage
            .first { $0.name.caseInsensitiveCompare("Sonnet") == .orderedSame }?
            .limit
        lastUpdated = data.lastUpdated
    }

    enum CodingKeys: String, CodingKey {
        case sessionUsage = "session_usage"
        case weeklyUsage = "weekly_usage"
        case scopedUsage = "scoped_usage"
        case spendUsage = "spend_usage"
        case sonnetUsage = "sonnet_usage"
        case lastUpdated = "last_updated"
    }

    /// Written explicitly so the optional keys encode as null instead of
    /// vanishing: the synthesized encoder drops nil, and a key that disappears
    /// on some accounts is a breaking change for anything reading it by name.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionUsage, forKey: .sessionUsage)
        try container.encode(weeklyUsage, forKey: .weeklyUsage)
        try container.encode(scopedUsage, forKey: .scopedUsage)
        try container.encode(spendUsage, forKey: .spendUsage)
        try container.encode(sonnetUsage, forKey: .sonnetUsage)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}
