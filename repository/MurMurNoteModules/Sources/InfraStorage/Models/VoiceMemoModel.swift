import Foundation
import SwiftData
import Domain

/// SwiftData @Model: 音声メモ
/// 01-Arch セクション5.2 準拠
@Model
public final class VoiceMemoModel {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var durationSeconds: Double
    public var audioFilePath: String
    public var audioFormatRawValue: String
    public var statusRawValue: String
    public var isFavorite: Bool

    @Relationship(deleteRule: .cascade, inverse: \TranscriptionModel.memo)
    public var transcription: TranscriptionModel?

    @Relationship(deleteRule: .cascade, inverse: \AISummaryModel.memo)
    public var aiSummary: AISummaryModel?

    @Relationship(deleteRule: .cascade, inverse: \EmotionAnalysisModel.memo)
    public var emotionAnalysis: EmotionAnalysisModel?

    @Relationship(deleteRule: .nullify)
    public var tags: [TagModel]

    public var audioFormat: AudioFormat {
        get { AudioFormat(rawValue: audioFormatRawValue) ?? .m4a }
        set { audioFormatRawValue = newValue.rawValue }
    }

    public var status: MemoStatus {
        get { MemoStatus(rawValue: statusRawValue) ?? .completed }
        set { statusRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        durationSeconds: Double = 0,
        audioFilePath: String,
        audioFormat: AudioFormat = .m4a,
        status: MemoStatus = .completed,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioFilePath = audioFilePath
        self.audioFormatRawValue = audioFormat.rawValue
        self.statusRawValue = status.rawValue
        self.isFavorite = isFavorite
        self.tags = []
    }

    /// ドメインエンティティに変換
    public func toEntity() -> VoiceMemoEntity {
        VoiceMemoEntity(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFilePath,
            audioFormat: audioFormat,
            status: status,
            isFavorite: isFavorite,
            transcription: transcription?.toEntity(),
            aiSummary: aiSummary?.toEntity(),
            emotionAnalysis: emotionAnalysis?.toEntity(),
            tags: tags.map { $0.toEntity() }
        )
    }

    /// ドメインエンティティから値を更新
    public func update(from entity: VoiceMemoEntity) {
        title = entity.title
        updatedAt = entity.updatedAt
        durationSeconds = entity.durationSeconds
        audioFilePath = entity.audioFilePath
        audioFormat = entity.audioFormat
        status = entity.status
        isFavorite = entity.isFavorite
    }
}
