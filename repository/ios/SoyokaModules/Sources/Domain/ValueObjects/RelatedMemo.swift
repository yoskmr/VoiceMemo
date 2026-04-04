import Foundation

/// 関連メモの表示情報（メモ詳細画面の「つながるきおく」セクション用）
/// TASK-0043: きおくのつながり Phase 1（REQ-033 / US-311 / AC-311）
public struct RelatedMemo: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let emotion: EmotionCategory?
    public let tags: [String]
    public let relevanceScore: Double  // 0.0〜1.0（FTS5 + タグスコア正規化）

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        emotion: EmotionCategory?,
        tags: [String],
        relevanceScore: Double
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.emotion = emotion
        self.tags = tags
        self.relevanceScore = relevanceScore
    }
}
