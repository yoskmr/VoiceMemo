import Foundation
import SwiftData
import Domain

/// SwiftData @Model: ユーザー設定
/// 01-Arch セクション5.2 準拠
@Model
public final class UserSettingsModel {
    @Attribute(.unique) public var id: UUID
    public var themeRawValue: String
    public var biometricAuthEnabled: Bool
    public var iCloudSyncEnabled: Bool
    public var preferredSTTEngineRawValue: String
    public var customDictionaryData: Data?
    public var aiProcessingCountThisMonth: Int
    public var lastAICountResetDate: Date

    public var theme: ThemeType {
        get { ThemeType(rawValue: themeRawValue) ?? .system }
        set { themeRawValue = newValue.rawValue }
    }

    public var preferredSTTEngine: STTEngineType {
        get { STTEngineType(rawValue: preferredSTTEngineRawValue) ?? .whisperKit }
        set { preferredSTTEngineRawValue = newValue.rawValue }
    }

    public var customDictionary: [String: String] {
        get {
            guard let data = customDictionaryData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            customDictionaryData = try? JSONEncoder().encode(newValue)
        }
    }

    public init(
        id: UUID = UUID(),
        theme: ThemeType = .system,
        biometricAuthEnabled: Bool = false,
        iCloudSyncEnabled: Bool = false,
        preferredSTTEngine: STTEngineType = .whisperKit,
        customDictionary: [String: String] = [:],
        aiProcessingCountThisMonth: Int = 0,
        lastAICountResetDate: Date = Date()
    ) {
        self.id = id
        self.themeRawValue = theme.rawValue
        self.biometricAuthEnabled = biometricAuthEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.preferredSTTEngineRawValue = preferredSTTEngine.rawValue
        self.customDictionaryData = try? JSONEncoder().encode(customDictionary)
        self.aiProcessingCountThisMonth = aiProcessingCountThisMonth
        self.lastAICountResetDate = lastAICountResetDate
    }

    /// ドメインエンティティに変換
    public func toEntity() -> UserSettingsEntity {
        UserSettingsEntity(
            id: id,
            theme: theme,
            biometricAuthEnabled: biometricAuthEnabled,
            iCloudSyncEnabled: iCloudSyncEnabled,
            preferredSTTEngine: preferredSTTEngine,
            customDictionary: customDictionary,
            aiProcessingCountThisMonth: aiProcessingCountThisMonth,
            lastAICountResetDate: lastAICountResetDate
        )
    }

    /// ドメインエンティティから値を更新
    public func update(from entity: UserSettingsEntity) {
        theme = entity.theme
        biometricAuthEnabled = entity.biometricAuthEnabled
        iCloudSyncEnabled = entity.iCloudSyncEnabled
        preferredSTTEngine = entity.preferredSTTEngine
        customDictionary = entity.customDictionary
        aiProcessingCountThisMonth = entity.aiProcessingCountThisMonth
        lastAICountResetDate = entity.lastAICountResetDate
    }
}
