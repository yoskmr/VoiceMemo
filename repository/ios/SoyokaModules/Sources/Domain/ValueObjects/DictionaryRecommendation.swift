import Foundation

/// 辞書レコメンド候補
public struct DictionaryRecommendation: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// 音声認識結果（読み）
    public let reading: String
    /// 正しい表記（ユーザーまたはAIが修正した表記）
    public let display: String
    /// 検出回数（2回以上で提案）
    public let occurrenceCount: Int
    /// 検出ソース
    public let source: Source

    public enum Source: String, Sendable, Equatable {
        case userEdit     // ユーザーが手動で修正
        case aiCorrection // AI整理で補正
    }

    public init(id: UUID = UUID(), reading: String, display: String, occurrenceCount: Int, source: Source) {
        self.id = id
        self.reading = reading
        self.display = display
        self.occurrenceCount = occurrenceCount
        self.source = source
    }
}
