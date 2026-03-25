import Foundation

/// 音声メモのドメインエンティティ
/// 01-Arch セクション5.2 準拠
public struct VoiceMemoEntity: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var durationSeconds: Double
    public var audioFilePath: String
    public var audioFormat: AudioFormat
    public var status: MemoStatus
    public var isFavorite: Bool
    public var transcription: TranscriptionEntity?
    public var aiSummary: AISummaryEntity?
    public var emotionAnalysis: EmotionAnalysisEntity?
    public var tags: [TagEntity]

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        durationSeconds: Double = 0,
        audioFilePath: String,
        audioFormat: AudioFormat = .m4a,
        status: MemoStatus = .completed,
        isFavorite: Bool = false,
        transcription: TranscriptionEntity? = nil,
        aiSummary: AISummaryEntity? = nil,
        emotionAnalysis: EmotionAnalysisEntity? = nil,
        tags: [TagEntity] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.durationSeconds = durationSeconds
        self.audioFilePath = audioFilePath
        self.audioFormat = audioFormat
        self.status = status
        self.isFavorite = isFavorite
        self.transcription = transcription
        self.aiSummary = aiSummary
        self.emotionAnalysis = emotionAnalysis
        self.tags = tags
    }
}
