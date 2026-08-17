//
//  UsageAPIResponse.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// `limits` is authoritative. The flat per-model fields (`seven_day_sonnet`,
/// `seven_day_opus`, ...) come back null and the API adds no new ones, so only
/// Sonnet is kept, for accounts still served the older shape.
struct UsageAPIResponse: Codable {
    let limits: [LimitEntryResponse]?
    let fiveHour: UsageLimitResponse?
    let sevenDay: UsageLimitResponse?
    let sevenDaySonnet: UsageLimitResponse?

    /// Extra-usage credits, in the API's current money shape.
    let spend: SpendResponse?

    /// The older credits block. Same numbers, flatter shape; still sent
    /// alongside `spend`, and the only source for accounts not yet migrated.
    let extraUsage: ExtraUsageResponse?

    init(
        fiveHour: UsageLimitResponse? = nil,
        sevenDay: UsageLimitResponse? = nil,
        sevenDaySonnet: UsageLimitResponse? = nil,
        limits: [LimitEntryResponse]? = nil,
        spend: SpendResponse? = nil,
        extraUsage: ExtraUsageResponse? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.limits = limits
        self.spend = spend
        self.extraUsage = extraUsage
    }

    enum CodingKeys: String, CodingKey {
        case limits
        case spend
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

/// ```json
/// "spend": { "used":  { "amount_minor": 2765, "currency": "USD", "exponent": 2 },
///            "limit": { "amount_minor": 5000, "currency": "USD", "exponent": 2 },
///            "enabled": true }
/// ```
struct SpendResponse: Codable {
    struct Money: Codable {
        let amountMinor: Int
        let currency: String?
        let exponent: Int?

        enum CodingKeys: String, CodingKey {
            case amountMinor = "amount_minor"
            case currency
            case exponent
        }
    }

    let used: Money?
    let limit: Money?
    let enabled: Bool?
}

/// ```json
/// "extra_usage": { "used_credits": 2765.0, "monthly_limit": 5000,
///                  "currency": "USD", "decimal_places": 2, "is_enabled": true }
/// ```
struct ExtraUsageResponse: Codable {
    let usedCredits: Double?
    let monthlyLimit: Double?
    let currency: String?
    let decimalPlaces: Int?
    let isEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case currency
        case decimalPlaces = "decimal_places"
        case isEnabled = "is_enabled"
    }
}

struct UsageLimitResponse: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct LimitEntryResponse: Codable {
    let kind: String
    let percent: Double
    let resetsAt: String?
    let scope: LimitScopeResponse?
    let isActive: Bool?

    init(
        kind: String,
        percent: Double,
        resetsAt: String?,
        scope: LimitScopeResponse? = nil,
        isActive: Bool? = nil
    ) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.scope = scope
        self.isActive = isActive
    }

    enum Kind {
        static let session = "session"
        static let weeklyAll = "weekly_all"
        static let headline = [session, weeklyAll]
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
        case isActive = "is_active"
    }

    var scopeDisplayName: String? {
        let names = [scope?.model?.displayName, scope?.surface?.displayName].compactMap { $0 }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }
}

struct LimitScopeResponse: Codable {
    let model: NamedScopeResponse?
    let surface: NamedScopeResponse?

    /// A scope shape we do not recognise must degrade to nil, not fail the response.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try? container.decodeIfPresent(NamedScopeResponse.self, forKey: .model)
        surface = try? container.decodeIfPresent(NamedScopeResponse.self, forKey: .surface)
    }
}

struct NamedScopeResponse: Codable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

enum MappingError: LocalizedError {
    case invalidDateFormat
    case missingCriticalField(field: String)

    var errorDescription: String? {
        switch self {
        case .invalidDateFormat:
            return "Server returned invalid date format"
        case .missingCriticalField(let field):
            return "Server response missing critical field: \(field)"
        }
    }
}

extension UsageAPIResponse {
    func toDomain() throws -> UsageData {
        guard let sessionEntry = entry(ofKind: LimitEntryResponse.Kind.session, legacy: fiveHour) else {
            throw MappingError.missingCriticalField(field: "five_hour")
        }
        // The weekly window is not critical. Accounts the API meters only on the
        // 5-hour window come back with no `weekly_all` entry and a null
        // `seven_day`, and failing the whole response over it threw away a
        // perfectly good session reading — blanking the meter completely.
        let weeklyEntry = entry(ofKind: LimitEntryResponse.Kind.weeklyAll, legacy: sevenDay)

        return UsageData(
            sessionUsage: try usageLimit(from: sessionEntry, fallback: Constants.Pacing.sessionWindow),
            weeklyUsage: try weeklyEntry.map { try usageLimit(from: $0, fallback: Constants.Pacing.weeklyWindow) },
            scopedUsage: try scopedUsage(),
            spendUsage: spendUsage(),
            lastUpdated: Date()
        )
    }

    /// Credits, from whichever block the account is served.
    ///
    /// `spend` wins: it carries the currency's exponent explicitly, so the
    /// amounts need no guessing. `extra_usage` is read only when `spend` is
    /// absent, and a cap of zero is treated as "no credit budget" rather than
    /// as a budget that is fully spent.
    private func spendUsage() -> SpendUsage? {
        if let spend, let used = spend.used, let limit = spend.limit, limit.amountMinor > 0 {
            return SpendUsage(
                usedMinor: used.amountMinor,
                limitMinor: limit.amountMinor,
                currencyCode: used.currency ?? limit.currency ?? "USD",
                exponent: used.exponent ?? limit.exponent ?? 2,
                isEnabled: spend.enabled ?? true
            )
        }

        guard let extraUsage,
              let used = extraUsage.usedCredits,
              let limit = extraUsage.monthlyLimit,
              limit > 0 else {
            return nil
        }

        return SpendUsage(
            usedMinor: Int(used.rounded()),
            limitMinor: Int(limit.rounded()),
            currencyCode: extraUsage.currency ?? "USD",
            exponent: extraUsage.decimalPlaces ?? 2,
            isEnabled: extraUsage.isEnabled ?? true
        )
    }

    private func entry(ofKind kind: String, legacy: UsageLimitResponse?) -> LimitEntryResponse? {
        if let entry = limits?.first(where: { $0.kind == kind }) {
            return entry
        }
        return legacy.map {
            LimitEntryResponse(kind: kind, percent: $0.utilization, resetsAt: $0.resetsAt)
        }
    }

    /// Any kind may carry a scope, but headline kinds are excluded so an entry the API
    /// later scopes cannot render both as a headline card and a scoped one.
    private func scopedUsage() throws -> [ScopedUsageLimit] {
        let scoped = try (limits ?? [])
            .filter { !LimitEntryResponse.Kind.headline.contains($0.kind) }
            .compactMap { entry -> ScopedUsageLimit? in
                guard let name = entry.scopeDisplayName else { return nil }
                return ScopedUsageLimit(
                    name: name,
                    limit: try usageLimit(from: entry, fallback: Constants.Pacing.weeklyWindow),
                    isActive: entry.isActive ?? false
                )
            }

        guard scoped.isEmpty, let sonnet = sevenDaySonnet else {
            return scoped
        }

        return [
            ScopedUsageLimit(
                name: "Sonnet",
                limit: try usageLimit(
                    from: LimitEntryResponse(
                        kind: "seven_day_sonnet",
                        percent: sonnet.utilization,
                        resetsAt: sonnet.resetsAt
                    ),
                    fallback: Constants.Pacing.weeklyWindow
                ),
                isActive: false
            )
        ]
    }

    private func usageLimit(from entry: LimitEntryResponse, fallback: TimeInterval) throws -> UsageLimit {
        UsageLimit(
            utilization: entry.percent,
            resetAt: try parseResetDate(
                from: entry.resetsAt,
                field: "\(entry.kind).resets_at",
                fallback: fallback
            ),
            isResetKnown: entry.resetsAt != nil
        )
    }

    private func parseResetDate(
        from rawValue: String?,
        field: String,
        fallback: TimeInterval
    ) throws -> Date {
        guard let rawValue else {
            return Date().addingTimeInterval(fallback)
        }
        guard let date = ISO8601Parsing.date(from: rawValue) else {
            throw MappingError.missingCriticalField(field: field)
        }
        return date
    }
}
