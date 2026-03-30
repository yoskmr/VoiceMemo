import Foundation

/// 週次レポート（Pro 限定）
public struct WeeklyReport: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// レポート対象期間
    public let weekStart: Date
    public let weekEnd: Date

    // --- 活動サマリー ---
    /// 今週のメモ数
    public let memoCount: Int
    /// 今週の合計録音時間（秒）
    public let totalRecordingDuration: TimeInterval
    /// よく使ったタグ（頻度順、上位5件）
    public let topTags: [TagFrequency]

    // --- 感情トレンド ---
    /// 今週の主要感情
    public let dominantEmotion: EmotionCategory?
    /// 感情分布（カテゴリ別の出現割合）
    public let emotionDistribution: [EmotionCategory: Double]
    /// 前週との感情変化
    public let emotionTrend: String?  // 例: "先週より穏やかな一週間でした"

    // --- 習慣 ---
    /// 連続記録日数（ストリーク）
    public let streakDays: Int
    /// 今週の記録日数（7日中何日）
    public let activeDays: Int

    // --- よく使った言葉 ---
    /// 頻出ワード（上位5件）
    public let topWords: [WordFrequency]

    // --- AIコメント ---
    /// AIからの一言コメント（ふりかえり風）
    public let aiComment: String?

    public init(
        id: UUID = UUID(),
        weekStart: Date,
        weekEnd: Date,
        memoCount: Int,
        totalRecordingDuration: TimeInterval,
        topTags: [TagFrequency],
        dominantEmotion: EmotionCategory?,
        emotionDistribution: [EmotionCategory: Double],
        emotionTrend: String?,
        streakDays: Int = 0,
        activeDays: Int = 0,
        topWords: [WordFrequency] = [],
        aiComment: String?
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.memoCount = memoCount
        self.totalRecordingDuration = totalRecordingDuration
        self.topTags = topTags
        self.dominantEmotion = dominantEmotion
        self.emotionDistribution = emotionDistribution
        self.emotionTrend = emotionTrend
        self.streakDays = streakDays
        self.activeDays = activeDays
        self.topWords = topWords
        self.aiComment = aiComment
    }
}

public struct TagFrequency: Equatable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct WordFrequency: Equatable, Sendable {
    public let word: String
    public let count: Int

    public init(word: String, count: Int) {
        self.word = word
        self.count = count
    }
}
