//
//  AppSettings.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// User preferences and app configuration
struct AppSettings: Codable, Equatable, Sendable {
    /// Refresh interval in seconds (60-600)
    var refreshInterval: TimeInterval

    /// Whether notifications are enabled
    var hasNotificationsEnabled: Bool

    /// Notification thresholds
    var notificationThresholds: NotificationThresholds

    /// Whether this is first launch
    var isFirstLaunch: Bool

    /// Last known organization ID (cached)
    var cachedOrganizationId: UUID?

    /// Model-scoped limits shown in the popover, by API display name.
    /// The models Claude currently meters separately are shown by default;
    /// a name the API introduces later stays hidden until asked for.
    var shownScopedModels: Set<String>

    /// Menu bar icon display style
    var iconStyle: IconStyle

    /// Whether menu bar icons are shown in color instead of monochrome.
    var isColoredIcon: Bool

    /// Days per week the weekly quota is expected to be consumed over (5-7).
    /// Sustainable weekly pace is measured against this instead of all 7 days.
    var weeklyPaceDays: Int

    /// Whether pace (burn rate) is the primary display instead of quota percentage,
    /// in both the menu bar and the popover.
    var isPaceFirstDisplay: Bool

    static let `default` = AppSettings(
        refreshInterval: 60,
        hasNotificationsEnabled: true,
        notificationThresholds: .default,
        isFirstLaunch: true,
        cachedOrganizationId: nil,
        shownScopedModels: ["Opus", "Sonnet", "Fable"],
        iconStyle: .battery,
        isColoredIcon: true,
        weeklyPaceDays: 7,
        isPaceFirstDisplay: false
    )

    enum CodingKeys: String, CodingKey {
        case refreshInterval = "refresh_interval"
        case hasNotificationsEnabled = "notifications_enabled"
        case notificationThresholds = "notification_thresholds"
        case isFirstLaunch = "is_first_launch"
        case cachedOrganizationId = "cached_organization_id"
        case shownScopedModels = "shown_scoped_models"
        case iconStyle = "icon_style"
        case isColoredIcon = "is_colored_icon"
        case weeklyPaceDays = "weekly_pace_days"
        case isPaceFirstDisplay = "pace_first_display"
    }

    /// Read-only: migrates settings saved before `shownScopedModels` existed.
    /// Kept out of `CodingKeys` so `encode` stays synthesized.
    private enum LegacyCodingKeys: String, CodingKey {
        case showSonnetUsage = "show_sonnet_usage"
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default

        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        hasNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hasNotificationsEnabled) ?? defaults.hasNotificationsEnabled
        notificationThresholds = try container.decodeIfPresent(NotificationThresholds.self, forKey: .notificationThresholds) ?? defaults.notificationThresholds
        isFirstLaunch = try container.decodeIfPresent(Bool.self, forKey: .isFirstLaunch) ?? defaults.isFirstLaunch
        cachedOrganizationId = try container.decodeIfPresent(UUID.self, forKey: .cachedOrganizationId)
        iconStyle = try container.decodeIfPresent(IconStyle.self, forKey: .iconStyle) ?? defaults.iconStyle
        isColoredIcon = try container.decodeIfPresent(Bool.self, forKey: .isColoredIcon) ?? defaults.isColoredIcon
        let decodedPaceDays = try container.decodeIfPresent(Int.self, forKey: .weeklyPaceDays) ?? defaults.weeklyPaceDays
        weeklyPaceDays = max(5, min(7, decodedPaceDays))
        isPaceFirstDisplay = try container.decodeIfPresent(Bool.self, forKey: .isPaceFirstDisplay) ?? defaults.isPaceFirstDisplay

        if let shown = try container.decodeIfPresent(Set<String>.self, forKey: .shownScopedModels) {
            shownScopedModels = shown
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let wasSonnetShown = try legacy.decodeIfPresent(Bool.self, forKey: .showSonnetUsage) ?? false
            shownScopedModels = wasSonnetShown ? ["Sonnet"] : defaults.shownScopedModels
        }
    }
}

extension AppSettings {
    /// Validate refresh interval is within bounds
    mutating func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(60, min(600, interval))
    }

    /// Span the weekly quota is expected to be consumed over, per `weeklyPaceDays`.
    var weeklyPacingDuration: TimeInterval {
        Constants.Pacing.weeklyPacingDuration(days: weeklyPaceDays)
    }

    /// Whether a model-scoped limit should appear in the popover
    func isScopedModelShown(_ name: String) -> Bool {
        shownScopedModels.contains(name)
    }

    mutating func setScopedModel(_ name: String, isShown: Bool) {
        if isShown {
            shownScopedModels.insert(name)
        } else {
            shownScopedModels.remove(name)
        }
    }
}
