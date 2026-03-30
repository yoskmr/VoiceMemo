import Foundation

/// ユーザー設定のドメインエンティティ
/// 01-Arch セクション5.2 準拠
public struct UserSettingsEntity: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var theme: ThemeType
    public var biometricAuthEnabled: Bool
    public var iCloudSyncEnabled: Bool
    public var preferredSTTEngine: STTEngineType
    public var customDictionary: [String: String]
    public var aiProcessingCountThisMonth: Int
    public var lastAICountResetDate: Date
    public var emotionAnalysisEnabled: Bool

    public init(
        id: UUID = UUID(),
        theme: ThemeType = .system,
        biometricAuthEnabled: Bool = false,
        iCloudSyncEnabled: Bool = false,
        preferredSTTEngine: STTEngineType = .whisperKit,
        customDictionary: [String: String] = [:],
        aiProcessingCountThisMonth: Int = 0,
        lastAICountResetDate: Date = Date(),
        emotionAnalysisEnabled: Bool = false
    ) {
        self.id = id
        self.theme = theme
        self.biometricAuthEnabled = biometricAuthEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.preferredSTTEngine = preferredSTTEngine
        self.customDictionary = customDictionary
        self.aiProcessingCountThisMonth = aiProcessingCountThisMonth
        self.lastAICountResetDate = lastAICountResetDate
        self.emotionAnalysisEnabled = emotionAnalysisEnabled
    }

    /// 月次AI処理カウントのリセット判定 (EC-014: 毎月1日 JST 0:00)
    public func shouldResetMonthlyCount() -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = Date()
        let lastMonth = calendar.component(.month, from: lastAICountResetDate)
        let currentMonth = calendar.component(.month, from: now)
        let lastYear = calendar.component(.year, from: lastAICountResetDate)
        let currentYear = calendar.component(.year, from: now)
        return lastYear != currentYear || lastMonth != currentMonth
    }
}
