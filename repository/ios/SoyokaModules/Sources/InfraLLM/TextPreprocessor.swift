import Foundation

/// LLM 処理前のテキスト前処理（ルールベース、LLM 不要）
public struct TextPreprocessor: Sendable {

    /// フィラーワードを除去してテキストを短縮する
    public static func removeFillers(_ text: String) -> String {
        var result = text

        // フィラーワードリスト（頻出順）
        let fillers = [
            "えっと", "えーっと", "えーと", "えっとー",
            "あのー", "あの", "あのね",
            "まあ", "まぁ",
            "なんか", "なんていうか",
            "そのー", "その",
            "ええと", "ええっと",
            "うーん", "うん", "うーんと",
            "ほら", "こう", "やっぱ",
            "なんだろう", "なんだろ",
        ]

        for filler in fillers {
            // フィラーの後に句読点・スペースが続くパターンを除去
            result = result.replacingOccurrences(of: filler + "、", with: "")
            result = result.replacingOccurrences(of: filler + "。", with: "。")
            result = result.replacingOccurrences(of: filler + " ", with: "")
            result = result.replacingOccurrences(of: filler + "\u{3000}", with: "")
            // 文頭のフィラー
            if result.hasPrefix(filler) {
                result = String(result.dropFirst(filler.count))
            }
        }

        // 連続する句読点を整理
        result = result.replacingOccurrences(of: "、、", with: "、")
        result = result.replacingOccurrences(of: "。。", with: "。")

        // 連続するスペースを整理
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
