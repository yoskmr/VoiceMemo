import Foundation

/// ルールベースのカスタム辞書後処理
/// LLMに辞書を渡すと過剰適用で破壊するため、
/// STT出力テキストに対してルールベースで置換を行う
public struct DictionaryPostProcessor: Sendable {

    public init() {}

    /// カスタム辞書エントリに基づいてテキストを補正する
    /// - Parameters:
    ///   - text: STTの文字起こしテキスト
    ///   - entries: カスタム辞書エントリ（reading: 読み, display: 正しい表記）
    /// - Returns: 補正後のテキスト
    public func apply(text: String, entries: [(reading: String, display: String)]) -> String {
        var result = text

        for entry in entries {
            let reading = entry.reading
            let display = entry.display

            // 読みと表記が同じなら置換不要
            guard reading != display else { continue }
            // 空の読みはスキップ
            guard !reading.isEmpty, !display.isEmpty else { continue }

            // ひらがな読み → 正しい表記に置換
            result = result.replacingOccurrences(of: reading, with: display)

            // カタカナ読み → 正しい表記に置換
            let katakana = reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading
            if katakana != reading {
                result = result.replacingOccurrences(of: katakana, with: display)
            }
        }

        return result
    }
}
