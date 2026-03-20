import Foundation
import SwiftData
import Domain

/// SwiftData @Model: 感情分析結果
/// 01-Arch セクション5.2 準拠、統合仕様書セクション3.2 準拠
@Model
public final class EmotionAnalysisModel {
    @Attribute(.unique) public var id: UUID
    public var memo: VoiceMemoModel?
    public var primaryEmotionRawValue: String
    public var confidence: Double
    public var emotionScoresData: Data?
    public var evidenceData: Data?
    public var analyzedAt: Date

    public var primaryEmotion: EmotionCategory {
        get { EmotionCategory(rawValue: primaryEmotionRawValue) ?? .neutral }
        set { primaryEmotionRawValue = newValue.rawValue }
    }

    public var emotionScores: [String: Double] {
        get {
            guard let data = emotionScoresData else { return [:] }
            return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        }
        set {
            emotionScoresData = try? JSONEncoder().encode(newValue)
        }
    }

    public var evidence: [[String: String]] {
        get {
            guard let data = evidenceData else { return [] }
            return (try? JSONDecoder().decode([[String: String]].self, from: data)) ?? []
        }
        set {
            evidenceData = try? JSONEncoder().encode(newValue)
        }
    }

    public init(
        id: UUID = UUID(),
        primaryEmotion: EmotionCategory = .neutral,
        confidence: Double = 0.0,
        emotionScores: [String: Double] = [:],
        evidence: [[String: String]] = [],
        analyzedAt: Date = Date()
    ) {
        self.id = id
        self.primaryEmotionRawValue = primaryEmotion.rawValue
        self.confidence = confidence
        self.emotionScoresData = try? JSONEncoder().encode(emotionScores)
        self.evidenceData = try? JSONEncoder().encode(evidence)
        self.analyzedAt = analyzedAt
    }

    /// ドメインエンティティに変換
    public func toEntity() -> EmotionAnalysisEntity {
        var scores: [EmotionCategory: Double] = [:]
        for (key, value) in emotionScores {
            if let category = EmotionCategory(rawValue: key) {
                scores[category] = value
            }
        }

        let sentimentEvidence: [SentimentEvidence] = evidence.compactMap { dict in
            guard let text = dict["text"],
                  let emotionStr = dict["emotion"],
                  let emotion = EmotionCategory(rawValue: emotionStr) else {
                return nil
            }
            return SentimentEvidence(text: text, emotion: emotion)
        }

        return EmotionAnalysisEntity(
            id: id,
            primaryEmotion: primaryEmotion,
            confidence: confidence,
            emotionScores: scores,
            evidence: sentimentEvidence,
            analyzedAt: analyzedAt
        )
    }
}
