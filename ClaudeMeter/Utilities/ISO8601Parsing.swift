//
//  ISO8601Parsing.swift
//  ClaudeMeter
//

import Foundation

/// Tolerant ISO8601 parsing for API timestamps.
///
/// Claude's usage endpoints are inconsistent about fractional seconds and zone
/// notation: `resets_at` arrives as `2026-08-19T03:59:59.870334+00:00` (six
/// fractional digits, numeric offset) on the OAuth endpoint and as
/// `2026-08-19T03:59:59Z` (no fractional digits) when a window has just rolled
/// over. `ISO8601DateFormatter` only accepts one of those two shapes per
/// configuration, so a single formatter silently fails half the time.
enum ISO8601Parsing {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fallbacks: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ssXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
    }()

    /// Parse an ISO8601 timestamp, accepting any fractional-second precision
    /// and both `Z` and `±HH:MM` zone designators.
    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = fractional.date(from: trimmed) { return date }
        if let date = whole.date(from: trimmed) { return date }

        for formatter in fallbacks {
            if let date = formatter.date(from: trimmed) { return date }
        }

        return nil
    }
}
