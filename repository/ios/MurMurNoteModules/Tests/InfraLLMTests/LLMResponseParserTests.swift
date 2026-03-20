import XCTest
@testable import Domain
@testable import InfraLLM

final class LLMResponseParserTests: XCTestCase {
    private var parser: LLMResponseParser!

    override func setUp() {
        super.setUp()
        parser = LLMResponseParser()
    }

    // MARK: - 正常系: 直接JSON

    func testParse_validJSON_success() throws {
        let raw = """
        {"title": "会議の要約", "brief": "本日の会議で議論した内容のまとめ", "tags": ["会議", "議事録"]}
        """

        let result = try parser.parse(raw, processingTimeMs: 200, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.summary?.title, "会議の要約")
        XCTAssertEqual(result.summary?.brief, "本日の会議で議論した内容のまとめ")
        XCTAssertEqual(result.tags.count, 2)
        XCTAssertEqual(result.tags[0].label, "会議")
        XCTAssertEqual(result.tags[1].label, "議事録")
        XCTAssertEqual(result.processingTimeMs, 200)
        XCTAssertEqual(result.provider, .onDeviceLlamaCpp)
    }

    // MARK: - 正常系: フェンスドコードブロック

    func testParse_fencedJSONCodeBlock_success() throws {
        let raw = """
        以下がJSON出力です:
        ```json
        {"title": "買い物リスト", "brief": "今週の買い物メモ", "tags": ["買い物", "生活"]}
        ```
        """

        let result = try parser.parse(raw, processingTimeMs: 150, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.summary?.title, "買い物リスト")
        XCTAssertEqual(result.summary?.brief, "今週の買い物メモ")
        XCTAssertEqual(result.tags.count, 2)
    }

    func testParse_fencedCodeBlockWithoutLanguage_success() throws {
        let raw = """
        結果:
        ```
        {"title": "アイデアメモ", "brief": "新機能のアイデアメモ", "tags": ["アイデア"]}
        ```
        """

        let result = try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.summary?.title, "アイデアメモ")
        XCTAssertEqual(result.tags.count, 1)
    }

    // MARK: - 正常系: 前後に余分なテキスト

    func testParse_jsonWithSurroundingText_success() throws {
        let raw = """
        以下のメモを要約しました。

        {"title": "プロジェクト報告", "brief": "進捗報告の要約", "tags": ["報告", "進捗"]}

        以上です。
        """

        let result = try parser.parse(raw, processingTimeMs: 300, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.summary?.title, "プロジェクト報告")
        XCTAssertEqual(result.tags.count, 2)
    }

    // MARK: - タイトル・タグの切り詰め

    func testParse_longTitle_truncatedTo20Characters() throws {
        let raw = """
        {"title": "これは二十文字を超える非常に長いタイトルです", "brief": "要約", "tags": ["タグ"]}
        """

        let result = try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)

        XCTAssertLessThanOrEqual(result.summary!.title.count, 20)
    }

    func testParse_moreThan3Tags_limitedTo3() throws {
        let raw = """
        {"title": "テスト", "brief": "要約", "tags": ["タグ1", "タグ2", "タグ3", "タグ4", "タグ5"]}
        """

        let result = try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.tags.count, 3)
    }

    func testParse_longTagLabel_truncatedTo15Characters() throws {
        let raw = """
        {"title": "テスト", "brief": "要約", "tags": ["これは十五文字を超えるとても長いタグラベルです"]}
        """

        let result = try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)

        XCTAssertLessThanOrEqual(result.tags[0].label.count, 15)
    }

    // MARK: - 空タグ

    func testParse_emptyTags_success() throws {
        let raw = """
        {"title": "テスト", "brief": "要約テキスト", "tags": []}
        """

        let result = try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.summary?.title, "テスト")
        XCTAssertTrue(result.tags.isEmpty)
    }

    // MARK: - 部分パース（一部フィールドの欠落）

    func testParse_missingTags_partialParse() throws {
        // tags フィールドが欠落しているが title/brief はある
        let raw = """
        {"title": "部分的", "brief": "一部欠落"}
        """

        // OnDeviceLLMOutput は tags が必須なので Decodable で失敗 -> 部分パースに入る
        let result = try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)

        XCTAssertEqual(result.summary?.title, "部分的")
        XCTAssertEqual(result.summary?.brief, "一部欠落")
    }

    // MARK: - 異常系

    func testParse_emptyString_throwsInvalidOutput() {
        XCTAssertThrowsError(try parser.parse("", processingTimeMs: 100, provider: .onDeviceLlamaCpp)) { error in
            XCTAssertEqual(error as? LLMError, .invalidOutput)
        }
    }

    func testParse_noJSON_throwsInvalidOutput() {
        XCTAssertThrowsError(
            try parser.parse("これはJSONではありません。", processingTimeMs: 100, provider: .onDeviceLlamaCpp)
        ) { error in
            XCTAssertEqual(error as? LLMError, .invalidOutput)
        }
    }

    func testParse_malformedJSON_throwsInvalidOutput() {
        // title も brief もなく、JSON としても不完全
        let raw = """
        {invalid json content}
        """

        XCTAssertThrowsError(try parser.parse(raw, processingTimeMs: 100, provider: .onDeviceLlamaCpp)) { error in
            XCTAssertEqual(error as? LLMError, .invalidOutput)
        }
    }

    func testParse_whitespaceOnly_throwsInvalidOutput() {
        XCTAssertThrowsError(try parser.parse("   \n\t  ", processingTimeMs: 100, provider: .onDeviceLlamaCpp)) { error in
            XCTAssertEqual(error as? LLMError, .invalidOutput)
        }
    }

    // MARK: - JSON抽出の単体テスト

    func testExtractJSON_directJSON() {
        let json = parser.extractJSON(from: "{\"key\": \"value\"}")
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("key"))
    }

    func testExtractJSON_fencedBlock() {
        let text = "テキスト\n```json\n{\"key\": \"value\"}\n```\n終わり"
        let json = parser.extractJSON(from: text)
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("key"))
    }

    func testExtractJSON_nestedBraces() {
        let text = "前文 {\"outer\": {\"inner\": \"value\"}} 後文"
        let json = parser.extractJSON(from: text)
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("inner"))
    }

    func testExtractJSON_noJSON_returnsNil() {
        let json = parser.extractJSON(from: "JSONなし")
        XCTAssertNil(json)
    }

    // MARK: - プロバイダ種別の透過テスト

    func testParse_cloudProvider_preservedInResponse() throws {
        let raw = """
        {"title": "テスト", "brief": "要約", "tags": ["タグ"]}
        """

        let result = try parser.parse(raw, processingTimeMs: 50, provider: .cloudGPT4oMini)

        XCTAssertEqual(result.provider, .cloudGPT4oMini)
    }
}
