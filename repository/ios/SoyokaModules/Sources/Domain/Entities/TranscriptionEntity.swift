import Foundation

/// 文字起こし結果のドメインエンティティ
/// 01-Arch セクション5.2 準拠
public struct TranscriptionEntity: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var fullText: String
    public var language: String
    public var engineType: STTEngineType
    public var confidence: Double
    public var processedAt: Date

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
        self.engineType = engineType
        self.confidence = confidence
        self.processedAt = processedAt
    }
}
