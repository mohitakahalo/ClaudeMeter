//
//  SpendUsage.swift
//  ClaudeMeter
//

import Foundation

/// Extra-usage credits — the spending that covers an account once it hits its
/// plan limits.
///
/// Amounts are kept in minor units with the API's own exponent (cents, for a
/// two-place USD amount) rather than converted to a Double on the way in, so a
/// balance is never a rounding artefact of the transport.
struct SpendUsage: Codable, Equatable, Sendable {
    let usedMinor: Int
    let limitMinor: Int
    let currencyCode: String
    let exponent: Int

    /// Whether the account has extra usage turned on. A disabled block still
    /// carries the last amounts, which is worth showing as history but not as a
    /// live budget.
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case usedMinor = "used_minor"
        case limitMinor = "limit_minor"
        case currencyCode = "currency"
        case exponent
        case isEnabled = "is_enabled"
    }
}

extension SpendUsage {
    /// Credit left before the cap. Never negative: spending past the cap is
    /// reported as nothing remaining, not as a negative balance.
    var remainingMinor: Int {
        max(limitMinor - usedMinor, 0)
    }

    /// Share of the cap consumed (0-100).
    var percentage: Double {
        guard limitMinor > 0 else { return 0 }
        return min(Double(usedMinor) / Double(limitMinor) * 100, 100)
    }

    /// Reuses the quota thresholds so a credit balance is coloured on the same
    /// scale as every other meter in the popover.
    var status: UsageStatus {
        switch percentage {
        case 0..<Constants.Thresholds.Status.warningStart:
            return .safe
        case Constants.Thresholds.Status.warningStart..<Constants.Thresholds.Status.criticalStart:
            return .warning
        default:
            return .critical
        }
    }

    var usedDescription: String { formatted(usedMinor) }
    var limitDescription: String { formatted(limitMinor) }
    var remainingDescription: String { formatted(remainingMinor) }

    private func formatted(_ minor: Int) -> String {
        let divisor = pow(10.0, Double(exponent))
        let amount = Double(minor) / divisor

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = exponent
        formatter.maximumFractionDigits = exponent

        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(exponent)f", amount)
    }
}
