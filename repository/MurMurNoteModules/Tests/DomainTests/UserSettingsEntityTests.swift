import XCTest
@testable import Domain

final class UserSettingsEntityTests: XCTestCase {

    func test_userSettingsEntity_creation_withDefaults() {
        let settings = UserSettingsEntity()

        XCTAssertEqual(settings.theme, .system)
        XCTAssertFalse(settings.biometricAuthEnabled)
        XCTAssertFalse(settings.iCloudSyncEnabled)
        XCTAssertEqual(settings.preferredSTTEngine, .whisperKit)
        XCTAssertTrue(settings.customDictionary.isEmpty)
        XCTAssertEqual(settings.aiProcessingCountThisMonth, 0)
    }

    func test_userSettingsEntity_customValues() {
        let settings = UserSettingsEntity(
            theme: .dark,
            biometricAuthEnabled: true,
            iCloudSyncEnabled: true,
            preferredSTTEngine: .speechAnalyzer,
            customDictionary: ["AI": "エーアイ"],
            aiProcessingCountThisMonth: 5
        )

        XCTAssertEqual(settings.theme, .dark)
        XCTAssertTrue(settings.biometricAuthEnabled)
        XCTAssertTrue(settings.iCloudSyncEnabled)
        XCTAssertEqual(settings.preferredSTTEngine, .speechAnalyzer)
        XCTAssertEqual(settings.customDictionary["AI"], "エーアイ")
        XCTAssertEqual(settings.aiProcessingCountThisMonth, 5)
    }

    // MARK: - shouldResetMonthlyCount テスト

    func test_shouldResetMonthlyCount_sameMonth_returnsFalse() {
        let settings = UserSettingsEntity(
            lastAICountResetDate: Date()
        )
        XCTAssertFalse(settings.shouldResetMonthlyCount())
    }

    func test_shouldResetMonthlyCount_differentMonth_returnsTrue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // 先月の日付を作成
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date())!

        let settings = UserSettingsEntity(
            lastAICountResetDate: lastMonth
        )
        XCTAssertTrue(settings.shouldResetMonthlyCount())
    }

    func test_shouldResetMonthlyCount_differentYear_returnsTrue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // 去年の同月の日付を作成
        let lastYear = calendar.date(byAdding: .year, value: -1, to: Date())!

        let settings = UserSettingsEntity(
            lastAICountResetDate: lastYear
        )
        XCTAssertTrue(settings.shouldResetMonthlyCount())
    }

    // MARK: - ThemeType テスト

    func test_themeType_rawValues() {
        XCTAssertEqual(ThemeType.system.rawValue, "system")
        XCTAssertEqual(ThemeType.light.rawValue, "light")
        XCTAssertEqual(ThemeType.dark.rawValue, "dark")
        XCTAssertEqual(ThemeType.journal.rawValue, "journal")
    }

    func test_themeType_codable() throws {
        for theme in [ThemeType.system, .light, .dark, .journal] {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(ThemeType.self, from: data)
            XCTAssertEqual(decoded, theme)
        }
    }
}
