import Foundation
import NaturalLanguage

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
        let originalWords = Set(tokenizeWords(original))
        let modifiedWords = Set(tokenizeWords(modified))

        // original にだけある単語（= 読み候補: STT の認識結果）
        let onlyInOriginal = originalWords.subtracting(modifiedWords)
        // modified にだけある単語（= 表示候補: AI/ユーザーが修正した表記）
        let onlyInModified = modifiedWords.subtracting(originalWords)

        var candidates: [(reading: String, display: String)] = []

        for reading in onlyInOriginal {
            for display in onlyInModified {
                if isValidPair(reading: reading, display: display) {
                    candidates.append((reading: reading, display: display))
                }
            }
        }

        return candidates
    }

    // MARK: - Private Helpers

    /// NLTokenizer で日本語テキストを単語分割
    private static func tokenizeWords(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.japanese)
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if word.count >= 2 {
                words.append(word)
            }
            return true
        }
        return words
    }

    /// 辞書登録候補として有効なペアか判定
    private static func isValidPair(reading: String, display: String) -> Bool {
        // 長さチェック: 2-8文字
        guard reading.count >= 2, reading.count <= 8 else { return false }
        guard display.count >= 2, display.count <= 8 else { return false }

        // 文字数差が2文字以内（同じ単語の別表記）
        guard abs(reading.count - display.count) <= 2 else { return false }

        // reading と display が同じなら除外
        guard reading != display else { return false }

        // display に漢字を含むこと（正しい表記は漢字が含まれる）
        guard containsKanji(display) else { return false }

        // 除外ワード（助詞・助動詞・接続詞・一般的すぎる単語）
        let excludeWords: Set<String> = [
            "ので", "ため", "から", "けど", "だけど", "でも",
            "それ", "これ", "あれ", "ここ", "そこ", "あそこ",
            "する", "ある", "いる", "なる", "できる",
            "こと", "もの", "ところ", "とき",
            "今日", "明日", "昨日", "今年", "去年", "来年",
            "本当", "最近", "結局", "やっぱり",
        ]
        if excludeWords.contains(reading) || excludeWords.contains(display) {
            return false
        }

        // 数字のみの単語は除外
        if reading.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        if display.allSatisfy({ $0.isNumber || $0 == "." }) { return false }

        return true
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
