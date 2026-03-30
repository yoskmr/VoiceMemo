import Foundation
import Testing
@testable import Domain
@testable import InfraLLM

@Suite("TextPreprocessor テスト")
struct TextPreprocessorTests {

    // MARK: - P0-1: removeUnnecessarySpaces

    @Test("日本語文字間のスペースが除去される")
    func test_removeUnnecessarySpaces_日本語文字間のスペース_除去される() {
        let input = "今日 は いい 天気 です"
        #expect(TextPreprocessor.removeUnnecessarySpaces(input) == "今日はいい天気です")
    }

    @Test("英数字間のスペースは保持される")
    func test_removeUnnecessarySpaces_英数字間のスペース_保持される() {
        let input = "iOS 17 のアプリ"
        #expect(TextPreprocessor.removeUnnecessarySpaces(input) == "iOS 17 のアプリ")
    }

    @Test("漢字-ひらがな境界のスペースが除去される")
    func test_removeUnnecessarySpaces_漢字ひらがな境界_除去される() {
        let input = "音声 認識 の 結果"
        #expect(TextPreprocessor.removeUnnecessarySpaces(input) == "音声認識の結果")
    }

    @Test("カタカナ-ひらがな混在のスペースが除去される")
    func test_removeUnnecessarySpaces_カタカナひらがな混在_除去される() {
        let input = "テスト の 結果 を 確認"
        #expect(TextPreprocessor.removeUnnecessarySpaces(input) == "テストの結果を確認")
    }

    @Test("英語と日本語が混在する場合、英語-日本語間のスペースは保持")
    func test_removeUnnecessarySpaces_英語日本語混在_英語側スペース保持() {
        let input = "Hello World の テスト"
        let result = TextPreprocessor.removeUnnecessarySpaces(input)
        #expect(result == "Hello World のテスト")
    }

    @Test("空文字列は空文字列を返す")
    func test_removeUnnecessarySpaces_空文字列() {
        #expect(TextPreprocessor.removeUnnecessarySpaces("") == "")
    }

    @Test("スペースのないテキストはそのまま返る")
    func test_removeUnnecessarySpaces_スペースなし_そのまま() {
        let input = "今日はいい天気です"
        #expect(TextPreprocessor.removeUnnecessarySpaces(input) == "今日はいい天気です")
    }

    // MARK: - P0-2: insertPunctuation

    @Test("文末パターン「です」の後のスペースに句点が挿入される")
    func test_insertPunctuation_です_句点挿入() {
        let input = "今日はいい天気です 明日も晴れます"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "今日はいい天気です。明日も晴れます")
    }

    @Test("文末パターン「ます」の後のスペースに句点が挿入される")
    func test_insertPunctuation_ます_句点挿入() {
        let input = "頑張ります また来ます"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "頑張ります。また来ます")
    }

    @Test("文末パターン「ました」の後のスペースに句点が挿入される")
    func test_insertPunctuation_ました_句点挿入() {
        let input = "完了しました 次に進みます"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "完了しました。次に進みます")
    }

    @Test("文末パターン「でした」の後のスペースに句点が挿入される")
    func test_insertPunctuation_でした_句点挿入() {
        let input = "楽しい一日でした また行きたいです"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "楽しい一日でした。また行きたいです")
    }

    @Test("「った」はLLM委託のため句点挿入しない")
    func test_insertPunctuation_った_句点挿入しない() {
        let input = "面白かった また見たい"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "面白かった また見たい")
    }

    @Test("「ない」はLLM委託のため句点挿入しない")
    func test_insertPunctuation_ない_句点挿入しない() {
        let input = "わからない 教えてほしい"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "わからない 教えてほしい")
    }

    @Test("文末パターン「ません」の後のスペースに句点が挿入される")
    func test_insertPunctuation_ません_句点挿入() {
        let input = "できません 別の方法を試します"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "できません。別の方法を試します")
    }

    @Test("既存の句点がある場合は二重挿入しない")
    func test_insertPunctuation_既存句点_二重挿入しない() {
        let input = "今日はいい天気です。明日も晴れます。"
        let result = TextPreprocessor.insertPunctuation(input)
        #expect(result == "今日はいい天気です。明日も晴れます。")
    }

    @Test("文末パターンなしのテキストはそのまま返る")
    func test_insertPunctuation_パターンなし_そのまま() {
        let input = "こんにちは"
        #expect(TextPreprocessor.insertPunctuation(input) == "こんにちは")
    }

    // MARK: - P0-3: removeFillers (level)

    @Test("level=.none の場合フィラーが保持される")
    func test_removeFillers_noneLevel_フィラー保持() {
        let input = "えーと、今日は天気がいいです"
        let result = TextPreprocessor.removeFillers(input, level: .none)
        #expect(result == input)
    }

    @Test("level=.light の場合思考中フィラーのみ除去される")
    func test_removeFillers_lightLevel_思考中フィラー除去() {
        let input = "えーと、今日は天気がいいです"
        let result = TextPreprocessor.removeFillers(input, level: .light)
        #expect(result == "今日は天気がいいです")
    }

    @Test("level=.light の場合口癖系フィラーは保持される")
    func test_removeFillers_lightLevel_口癖系フィラー保持() {
        let input = "なんか、面白かった"
        let result = TextPreprocessor.removeFillers(input, level: .light)
        // .light では「なんか」は除去対象外
        #expect(result.contains("なんか"))
    }

    @Test("level=.aggressive の場合口癖系フィラーも除去される")
    func test_removeFillers_aggressiveLevel_口癖系フィラー除去() {
        let input = "なんか、面白かった"
        let result = TextPreprocessor.removeFillers(input, level: .aggressive)
        #expect(!result.contains("なんか"))
    }

    @Test("level=.aggressive の場合相槌系フィラーも除去される")
    func test_removeFillers_aggressiveLevel_相槌系フィラー除去() {
        let input = "はい、そうですね、わかりました"
        let result = TextPreprocessor.removeFillers(input, level: .aggressive)
        #expect(!result.contains("はい"))
        #expect(!result.contains("そうですね"))
    }

    @Test("デフォルト引数（level省略）は .light として動作する")
    func test_removeFillers_デフォルト引数_lightと同じ() {
        let input = "えーと、今日は天気がいいです"
        let withDefault = TextPreprocessor.removeFillers(input)
        let withLight = TextPreprocessor.removeFillers(input, level: .light)
        #expect(withDefault == withLight)
    }

    @Test("複数のフィラーが連続する場合にすべて除去される（.aggressive）")
    func test_removeFillers_aggressiveLevel_複数フィラー連続() {
        let input = "えーと なんか まあ すごかった"
        let result = TextPreprocessor.removeFillers(input, level: .aggressive)
        #expect(!result.contains("えーと"))
        #expect(!result.contains("なんか"))
        #expect(!result.contains("まあ"))
        #expect(result.contains("すごかった"))
    }

    @Test("空文字列は空文字列を返す")
    func test_removeFillers_空文字列() {
        #expect(TextPreprocessor.removeFillers("", level: .light) == "")
    }

    // MARK: - 負例テスト（誤除去・誤変換の防止）

    @Test("insertPunctuation: 文中の「ない」はスペースがなければ句点挿入しない")
    func test_insertPunctuation_文中のない_スペースなし_変換しない() {
        let input = "問題ない方法を探す"
        #expect(TextPreprocessor.insertPunctuation(input) == "問題ない方法を探す")
    }

    @Test("removeFillers: aggressive でも内容語「その」は保持される")
    func test_removeFillers_aggressive_内容語その_保持() {
        let input = "その本を読んだ"
        let result = TextPreprocessor.removeFillers(input, level: .aggressive)
        #expect(result.contains("その本"))
    }

    @Test("removeFillers: aggressive でも内容語「でも」は保持される")
    func test_removeFillers_aggressive_内容語でも_保持() {
        let input = "でもそれは正しい"
        let result = TextPreprocessor.removeFillers(input, level: .aggressive)
        // 「でも」は文頭で後にスペースがないため保持される
        #expect(result.contains("でも"))
    }

    @Test("removeFillers: フィラー「その」は区切り文字が後続する場合のみ除去")
    func test_removeFillers_aggressive_その_区切り文字あり_除去() {
        let input = "その、あの本が面白かった"
        let result = TextPreprocessor.removeFillers(input, level: .aggressive)
        #expect(!result.hasPrefix("その"))
    }
}
