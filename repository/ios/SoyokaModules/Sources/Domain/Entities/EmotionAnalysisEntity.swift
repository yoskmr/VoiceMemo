import Foundation

/// 感情分析結果のドメインエンティティ
/// 01-Arch セクション5.2 準拠、統合仕様書セクション3.2 準拠
public struct EmotionAnalysisEntity: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var primaryEmotion: EmotionCategory
    public var confidence: Double
    public var emotionScores: [EmotionCategory: Double]
    public var evidence: [SentimentEvidence]
    public var analyzedAt: Date

    public init(
        id: UUID = UUID(),
        primaryEmotion: EmotionCategory = .neutral,
        confidence: Double = 0.0,
        emotionScores: [EmotionCategory: Double] = [:],
        evidence: [SentimentEvidence] = [],
        analyzedAt: Date = Date()
    ) {
        self.id = id
        self.primaryEmotion = primaryEmotion
        self.confidence = confidence
        self.emotionScores = emotionScores
        self.evidence = evidence
        self.analyzedAt = analyzedAt
    }
}

/// 感情分析の根拠テキスト
public struct SentimentEvidence: Sendable, Equatable, Codable {
    public let text: String
    public let emotion: EmotionCategory

    public init(text: String, emotion: EmotionCategory) {
        self.text = text
        self.emotion = emotion
    }
}
