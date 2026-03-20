import Foundation
import SwiftData
import Domain

/// SwiftData @Model: AI要約結果
/// 01-Arch セクション5.2 準拠
@Model
public final class AISummaryModel {
    @Attribute(.unique) public var id: UUID
    public var memo: VoiceMemoModel?
    public var title: String
    public var summaryText: String
    public var keyPointsData: Data?
    public var providerTypeRawValue: String
    public var isOnDevice: Bool
    public var generatedAt: Date

    public var providerType: LLMProviderType {
        get { LLMProviderType(rawValue: providerTypeRawValue) ?? .onDeviceLlamaCpp }
        set { providerTypeRawValue = newValue.rawValue }
    }

    public var keyPoints: [String] {
        get {
            guard let data = keyPointsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            keyPointsData = try? JSONEncoder().encode(newValue)
        }
    }

    public init(
        id: UUID = UUID(),
        title: String = "",
        summaryText: String,
        keyPoints: [String] = [],
        providerType: LLMProviderType = .onDeviceLlamaCpp,
        isOnDevice: Bool = true,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summaryText = summaryText
        self.keyPointsData = try? JSONEncoder().encode(keyPoints)
        self.providerTypeRawValue = providerType.rawValue
        self.isOnDevice = isOnDevice
        self.generatedAt = generatedAt
    }

    /// ドメインエンティティに変換
    public func toEntity() -> AISummaryEntity {
        AISummaryEntity(
            id: id,
            title: title,
            summaryText: summaryText,
            keyPoints: keyPoints,
            providerType: providerType,
            isOnDevice: isOnDevice,
            generatedAt: generatedAt
        )
    }
}
