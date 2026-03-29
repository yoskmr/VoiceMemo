import Foundation

/// テキストの差分から辞書レコメンド候補を検出するエンジン
public struct DictionaryRecommendationEngine: Sendable {

    /// 2つのテキストの差分から変更された単語ペアを検出
    /// - Parameters:
    ///   - original: 変更前テキスト（STT原文またはAI整理前）
    ///   - modified: 変更後テキスト（ユーザー編集後またはAI整理後）
    ///   - source: 検出ソース
    /// - Returns: 検出された単語ペアのリスト
    public static func detectChanges(
        original: String,
        modified: String,
        source: DictionaryRecommendation.Source
    ) -> [(reading: String, display: String)] {
        let originalWords = tokenize(original)
        let modifiedWords = tokenize(modified)

        var changes: [(reading: String, display: String)] = []

        // 簡易差分: 同じ位置で異なる単語を検出
        let minCount = min(originalWords.count, modifiedWords.count)
        for i in 0..<minCount {
            let orig = originalWords[i]
            let mod = modifiedWords[i]
            if orig != mod && !orig.isEmpty && !mod.isEmpty {
                // ひらがな/カタカナ → 漢字 の変更パターンを優先
                if isLikelyReading(orig) && containsKanji(mod) {
                    changes.append((reading: orig, display: mod))
                }
            }
        }

        return changes
    }

    // MARK: - Private Helpers

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet.punctuationCharacters)
            .union(CharacterSet(charactersIn: "。、！？「」『』（）\n")))
            .filter { !$0.isEmpty }
    }

    private static func isLikelyReading(_ text: String) -> Bool {
        let hiraganaKatakana = text.unicodeScalars.filter {
            CharacterSet(charactersIn: "\u{3040}"..."\u{309F}").contains($0) ||
            CharacterSet(charactersIn: "\u{30A0}"..."\u{30FF}").contains($0)
        }
        return Double(hiraganaKatakana.count) / Double(max(text.count, 1)) > 0.5
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}").contains($0)
        }
    }
}

/// レコメンド候補の蓄積ストア（UserDefaults）
public final class RecommendationStore: @unchecked Sendable {
    private static let key = "dictionaryRecommendationCandidates"

    /// 候補を記録（出現回数を蓄積）
    public static func record(reading: String, display: String, source: DictionaryRecommendation.Source) {
        var candidates = loadCandidates()
        let candidateKey = "\(reading)→\(display)"
        if var existing = candidates[candidateKey] {
            existing.count += 1
            existing.lastSource = source.rawValue
            candidates[candidateKey] = existing
        } else {
            candidates[candidateKey] = CandidateRecord(
                reading: reading,
                display: display,
                count: 1,
                lastSource: source.rawValue
            )
        }
        saveCandidates(candidates)
    }

    /// 提案可能な候補を取得（出現2回以上）
    public static func fetchRecommendations() -> [DictionaryRecommendation] {
        loadCandidates()
            .values
            .filter { $0.count >= 2 }
            .map { record in
                DictionaryRecommendation(
                    reading: record.reading,
                    display: record.display,
                    occurrenceCount: record.count,
                    source: DictionaryRecommendation.Source(rawValue: record.lastSource) ?? .userEdit
                )
            }
            .sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    /// 候補を削除（登録済み or スキップ済み）
    public static func dismiss(reading: String, display: String) {
        var candidates = loadCandidates()
        candidates.removeValue(forKey: "\(reading)→\(display)")
        saveCandidates(candidates)
    }

    // MARK: - Private

    private struct CandidateRecord: Codable {
        var reading: String
        var display: String
        var count: Int
        var lastSource: String
    }

    private static func loadCandidates() -> [String: CandidateRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CandidateRecord].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveCandidates(_ candidates: [String: CandidateRecord]) {
        if let data = try? JSONEncoder().encode(candidates) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
