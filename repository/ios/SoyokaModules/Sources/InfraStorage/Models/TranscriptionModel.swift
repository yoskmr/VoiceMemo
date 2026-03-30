import Foundation
import SwiftData
import Domain

/// SwiftData @Model: 文字起こし結果
/// 01-Arch セクション5.2 準拠
@Model
public final class TranscriptionModel {
    @Attribute(.unique) public var id: UUID
    public var memo: VoiceMemoModel?
    public var fullText: String
    public var language: String
    public var engineTypeRawValue: String
    public var confidence: Double
    public var processedAt: Date

    public var engineType: STTEngineType {
        get { STTEngineType(rawValue: engineTypeRawValue) ?? .whisperKit }
        set { engineTypeRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        fullText: String,
        language: String = "ja-JP",
        engineType: STTEngineType = .whisperKit,
        confidence: Double = 0.0,
        processedAt: Date = Date()
    ) {
        self.id = id
        self.fullText = fullText
        self.language = language
        self.engineTypeRawValue = engineType.rawValue
        self.confidence = confidence
        self.processedAt = processedAt
    }

    /// ドメインエンティティに変換
    public func toEntity() -> TranscriptionEntity {
        TranscriptionEntity(
            id: id,
            fullText: fullText,
            language: language,
            engineType: engineType,
            confidence: confidence,
            processedAt: processedAt
        )
    }
}
