import Foundation

/// AI整理結果のフィードバックをUserDefaultsに蓄積するストア
public struct AIFeedbackStore: Sendable {
    private static let storageKey = "aiFeedbackList"

    /// フィードバックを保存する
    public static func saveFeedback(_ feedback: AIFeedback) {
        var list = loadAllFeedback()
        // 同一メモのフィードバックは上書き
        list.removeAll { $0.memoID == feedback.memoID }
        list.append(feedback)
        save(list)
    }

    /// 蓄積された全フィードバックを取得する
    public static func loadAllFeedback() -> [AIFeedback] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([AIFeedback].self, from: data)
        } catch {
            return []
        }
    }

    /// 特定メモへのフィードバックを取得する（未フィードバックならnil）
    public static func feedbackForMemo(_ memoID: UUID) -> AIFeedback? {
        loadAllFeedback().first { $0.memoID == memoID }
    }

    /// 集計: ポジティブ/ネガティブの件数
    public static func summary() -> (positive: Int, negative: Int) {
        let all = loadAllFeedback()
        let positive = all.filter(\.isPositive).count
        let negative = all.count - positive
        return (positive: positive, negative: negative)
    }

    // MARK: - Private

    private static func save(_ list: [AIFeedback]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
