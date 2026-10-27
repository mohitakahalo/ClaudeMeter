//
//  ScopedUsageSettingsTests.swift
//  ClaudeMeterTests
//

import XCTest
@testable import ClaudeMeter

final class ScopedUsageSettingsTests: XCTestCase {

    // MARK: - Settings migration

    /// The models Claude currently meters separately, shown unless the user hides them.
    private let defaultShownModels: Set<String> = ["Opus", "Sonnet", "Fable"]

    /// The pre-1.4.2 flag governed a Sonnet-only field the API now returns as
    /// null, so it says nothing about today's scoped limits either way.
    func test_decode_withLegacyShowSonnetTrue_takesDefaults() throws {
        let settings = try decodeSettings(#"{"show_sonnet_usage": true}"#)

        XCTAssertEqual(settings.shownScopedModels, defaultShownModels)
    }

    func test_decode_withLegacyShowSonnetFalse_takesDefaults() throws {
        let settings = try decodeSettings(#"{"show_sonnet_usage": false}"#)

        XCTAssertEqual(settings.shownScopedModels, defaultShownModels)
    }

    /// The settings shape written by the 1.4.0 release.
    func test_decode_settingsFromPreviousRelease_migratesCleanly() throws {
        let settings = try decodeSettings("""
        {"is_first_launch":false,"refresh_interval":60,"icon_style":"dualBar",
         "show_sonnet_usage":false,"is_colored_icon":false,"notifications_enabled":true,
         "notification_thresholds":{"critical_threshold":90,"notify_on_reset":true,"warning_threshold":75},
         "cached_organization_id":"00000000-0000-0000-0000-000000000000"}
        """)

        // Unrelated preferences survive
        XCTAssertEqual(settings.iconStyle, .dualBar)
        XCTAssertFalse(settings.isColoredIcon)
        XCTAssertEqual(settings.refreshInterval, 60)

        XCTAssertEqual(settings.shownScopedModels, defaultShownModels)
    }

    func test_decode_withShownScopedModels_roundTrips() throws {
        let settings = try decodeSettings(#"{"shown_scoped_models": ["Fable"]}"#)

        XCTAssertTrue(settings.isScopedModelShown("Fable"))
        XCTAssertFalse(settings.isScopedModelShown("Opus"))
    }

    /// Hiding every model is a choice, not a missing key, and must survive a relaunch.
    func test_decode_withEmptyShownScopedModels_showsNothing() throws {
        let settings = try decodeSettings(#"{"shown_scoped_models": []}"#)

        XCTAssertTrue(settings.shownScopedModels.isEmpty)
        XCTAssertFalse(settings.isScopedModelShown("Fable"))
    }

    func test_decode_withNeitherKey_takesDefaults() throws {
        let settings = try decodeSettings("{}")

        XCTAssertEqual(settings.shownScopedModels, defaultShownModels)
    }

    /// A model the API introduces later stays hidden until asked for.
    func test_default_hidesModelsNotYetMetered() {
        XCTAssertFalse(AppSettings.default.isScopedModelShown("Haiku"))
    }

    func test_setScopedModel_togglesVisibility() {
        var settings = AppSettings.default

        settings.setScopedModel("Fable", isShown: false)
        XCTAssertFalse(settings.isScopedModelShown("Fable"))
        XCTAssertEqual(settings.shownScopedModels, ["Opus", "Sonnet"])

        settings.setScopedModel("Fable", isShown: true)
        XCTAssertTrue(settings.isScopedModelShown("Fable"))
        XCTAssertEqual(settings.shownScopedModels, defaultShownModels)
    }

    // MARK: - Public JSON export

    /// `~/.claudemeter/usage.json` is a documented contract for statusline scripts.
    func test_export_stillEmitsSonnetUsageForExternalTools() throws {
        let json = try exportJSON(makeUsageData(percentage: 10, scoped: [("Sonnet", 25), ("Fable", 23)]))

        let sonnet = try XCTUnwrap(json["sonnet_usage"] as? [String: Any])
        XCTAssertEqual(sonnet["utilization"] as? Double, 25)

        let scoped = try XCTUnwrap(json["scoped_usage"] as? [[String: Any]])
        XCTAssertEqual(scoped.compactMap { $0["name"] as? String }, ["Sonnet", "Fable"])
    }

    /// The key stays present as null: scripts read it by name, and a key that
    /// vanishes on some accounts is a breaking change for them.
    func test_export_withoutSonnet_emitsNullLegacyKey() throws {
        let json = try exportJSON(makeUsageData(percentage: 10, scoped: [("Fable", 23)]))

        XCTAssertTrue(json["sonnet_usage"] is NSNull)
        XCTAssertEqual((json["scoped_usage"] as? [[String: Any]])?.count, 1)
    }

    func test_decode_legacyCacheWithSonnetUsage_becomesScopedLimit() throws {
        let json = """
        {
          "session_usage": { "utilization": 40, "reset_at": "2026-07-13T21:19:59Z" },
          "weekly_usage": { "utilization": 50, "reset_at": "2026-07-19T10:59:59Z" },
          "sonnet_usage": { "utilization": 25, "reset_at": "2026-07-19T10:59:59Z" },
          "last_updated": "2026-07-13T18:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try decoder.decode(UsageData.self, from: json)

        XCTAssertEqual(data.scopedUsage.map(\.name), ["Sonnet"])
        XCTAssertEqual(data.scopedUsage.first?.limit.utilization, 25)
    }

    // MARK: - Helpers

    private func decodeSettings(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
    }

    private func exportJSON(_ data: UsageData) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(UsageExportPayload(data))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    }
}
