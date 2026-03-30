import Domain
import Foundation

/// LLM 処理前のテキスト前処理（ルールベース、LLM 不要）
public struct TextPreprocessor: Sendable {

    // MARK: - 日本語スペース除去

    /// 日本語テキスト中の不要なスペースを除去する
    /// Apple Speech Framework が漢字-ひらがな境界に挿入する半角スペースを除去し、
    /// 英数字間のスペースは保持する。
    public static func removeUnnecessarySpaces(_ text: String) -> String {
        // lookahead で隣接する日本語文字ペアを1パスで処理
        let pattern = "([\\p{Han}\\p{Hiragana}\\p{Katakana}]) (?=[\\p{Han}\\p{Hiragana}\\p{Katakana}])"
        return text.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }

    // MARK: - 句読点自動挿入

    /// 文末パターンを検出して句点（。）を自動挿入する
    /// STTエンジン出力に句読点が不足する場合にルールベースで補完する。
    /// 既存の句点がある場合は二重挿入しない。
    public static func insertPunctuation(_ text: String) -> String {
        // 文末パターン: 「です」「ます」「ました」「でした」「ません」の後にスペースが続く場合
        // DES-006「高確信度パターンのみ処理」: 「った」「ない」は連体修飾での誤検出リスクが高いためLLM委託
        let sentenceEndPattern = "(です|ます|ました|でした|ません) "
        var result = text.replacingOccurrences(
            of: sentenceEndPattern, with: "$1。", options: .regularExpression
        )
        // 二重句点を防止
        result = result.replacingOccurrences(of: "。。", with: "。")
        return result
    }

    // MARK: - フィラー除去（レベル設定対応）

    /// フィラーワードを除去してテキストを短縮する
    /// - Parameters:
    ///   - text: 入力テキスト
    ///   - level: フィラー除去レベル（デフォルト: .light）
    /// - Returns: フィラー除去後のテキスト
    public static func removeFillers(_ text: String, level: FillerRemovalLevel = .light) -> String {
        guard level != .none else { return text }
        var result = text

        // .light: 思考中フィラー6語のみ除去
        let lightFillers = [
            "えっと", "えーっと", "えーと", "えっとー",
            "あのー", "あの",
            "ええと", "ええっと",
            "うーん", "うーんと",
            "そのー",
        ]

        // .aggressive: 口癖系・相槌系も追加除去
        let aggressiveFillers = [
            "あのね",
            "まあ", "まぁ",
            "なんか", "なんていうか",
            "その",
            "うん",
            "ほら", "こう", "やっぱ", "やっぱり",
            "なんだろう", "なんだろ",
            "ていうか", "っていうか",
            "はい", "そうですね", "そうそう",
            "だから", "でも", "けど",
            "ちょっと",
        ]

        let fillers: [String]
        switch level {
        case .none:
            return text
        case .light:
            fillers = lightFillers
        case .aggressive:
            fillers = lightFillers + aggressiveFillers
        }

        for filler in fillers {
            // フィラーの後に句読点・スペースが続くパターンを除去
            result = result.replacingOccurrences(of: filler + "、", with: "")
            result = result.replacingOccurrences(of: filler + "。", with: "。")
            result = result.replacingOccurrences(of: filler + " ", with: "")
            result = result.replacingOccurrences(of: filler + "\u{3000}", with: "")
            // 文頭のフィラー（後続が区切り文字の場合のみ除去）
            if result.hasPrefix(filler) {
                let afterFiller = result.dropFirst(filler.count)
                if afterFiller.isEmpty
                    || afterFiller.first == "、"
                    || afterFiller.first == "。"
                    || afterFiller.first == " "
                    || afterFiller.first == "\u{3000}" {
                    result = String(afterFiller)
                }
            }
        }

        // 連続する句読点を整理
        result = result.replacingOccurrences(of: "、、", with: "、")
        result = result.replacingOccurrences(of: "。。", with: "。")

        // 連続するスペースを整理
        result = result.replacingOccurrences(of: " +", with: " ", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
