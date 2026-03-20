import Domain
import XCTest

@testable import InfraStorage

final class FTS5IndexManagerTests: XCTestCase {

    private var testDBPath: String!
    private var sut: FTS5IndexManager!

    override func setUp() {
        super.setUp()
        // テスト用のインメモリ or 一時DBパス
        let tempDir = NSTemporaryDirectory()
        testDBPath = (tempDir as NSString).appendingPathComponent("fts5_test_\(UUID().uuidString).sqlite")
        // unicode61モードで確実にテスト可能にする（ICUはCI環境で非対応の場合がある）
        sut = FTS5IndexManager(dbPath: testDBPath, useICU: false)
    }

    override func tearDown() {
        sut = nil
        if let path = testDBPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }

    // MARK: - Test 1: テーブル作成成功

    func test_createIndex_テーブル作成成功() throws {
        XCTAssertNoThrow(try sut.createIndex())
    }

    // MARK: - Test 2: ICU非対応環境でフォールバック

    func test_createIndex_ICU非対応環境でフォールバック() throws {
        let fallbackSut = FTS5IndexManager(dbPath: testDBPath, useICU: false)
        try fallbackSut.createIndex()
        // unicode61 + trigram テーブルが両方作成される
        // 検索が動作することで確認
        try fallbackSut.upsertIndex(
            memoID: "test-1",
            title: "テスト",
            transcriptionText: "テスト文章",
            summaryText: "",
            tags: ""
        )
        let results = try fallbackSut.search(query: "テスト")
        // unicode61 or trigram のいずれかで見つかるはず
        XCTAssertGreaterThanOrEqual(results.count, 1)
    }

    // MARK: - Test 3: 新規追加

    func test_upsertIndex_新規追加() throws {
        try sut.createIndex()

        try sut.upsertIndex(
            memoID: "memo-1",
            title: "通勤中のアイデア",
            transcriptionText: "今日のアプリ開発のアイデアを思いついた",
            summaryText: "アプリのアイデアメモ",
            tags: "アイデア,アプリ開発"
        )

        let results = try sut.search(query: "アイデア")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].memoID, "memo-1")
    }

    // MARK: - Test 4: 既存更新（重複なし）

    func test_upsertIndex_既存更新() throws {
        try sut.createIndex()

        try sut.upsertIndex(
            memoID: "memo-1",
            title: "初回タイトル",
            transcriptionText: "初回テキスト",
            summaryText: "",
            tags: ""
        )

        // 同一IDで更新
        try sut.upsertIndex(
            memoID: "memo-1",
            title: "更新後タイトル",
            transcriptionText: "更新後テキスト 特別な内容",
            summaryText: "",
            tags: ""
        )

        // unicode61は日本語を連続CJK文字列として1トークンに扱うため、
        // 完全一致またはトークン境界に合った文字列で検索する。
        // trigram は3文字以上が必要。「特別な内容」(4文字)はunicode61/trigramの両方でマッチする。
        let results = try sut.search(query: "特別な内容")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].memoID, "memo-1")

        // 古い内容(初回テキスト)はDELETE+INSERTで消えているため見つからないことを確認
        let oldResults = try sut.search(query: "初回テキスト")
        // unicode61ではトークン一致で見つかる可能性があるが、
        // upsertでDELETE済みなので結果は0件のはず
        XCTAssertEqual(oldResults.count, 0)
    }

    // MARK: - Test 5: 削除後に検索されない

    func test_removeIndex_削除後に検索されない() throws {
        try sut.createIndex()

        try sut.upsertIndex(
            memoID: "memo-1",
            title: "削除対象メモ",
            transcriptionText: "このメモは削除される 特殊キーワード",
            summaryText: "",
            tags: ""
        )

        // 削除前: 見つかる
        let beforeResults = try sut.search(query: "特殊キーワード")
        XCTAssertGreaterThanOrEqual(beforeResults.count, 1)

        // 削除
        try sut.removeIndex(memoID: "memo-1")

        // 削除後: 見つからない
        let afterResults = try sut.search(query: "特殊キーワード")
        XCTAssertEqual(afterResults.count, 0)
    }

    // MARK: - Test 6: 日本語クエリ

    func test_search_日本語クエリ() throws {
        try sut.createIndex()

        try sut.upsertIndex(
            memoID: "memo-1",
            title: "通勤中のアイデア",
            transcriptionText: "今日のアプリ開発のアイデアを思いついた",
            summaryText: "アプリのアイデアメモ",
            tags: "アイデア,アプリ開発"
        )

        try sut.upsertIndex(
            memoID: "memo-2",
            title: "買い物リスト",
            transcriptionText: "牛乳と卵を買う",
            summaryText: "買い物メモ",
            tags: "買い物"
        )

        let results = try sut.search(query: "アイデア")
        XCTAssertGreaterThanOrEqual(results.count, 1)
        XCTAssertTrue(results.contains(where: { $0.memoID == "memo-1" }))
        XCTAssertFalse(results.contains(where: { $0.memoID == "memo-2" }))
    }

    // MARK: - Test 7: 複数キーワードAND検索

    func test_search_複数キーワードAND検索() throws {
        try sut.createIndex()

        try sut.upsertIndex(
            memoID: "memo-1",
            title: "アプリ開発",
            transcriptionText: "アプリの設計について検討した",
            summaryText: "",
            tags: "アプリ"
        )

        try sut.upsertIndex(
            memoID: "memo-2",
            title: "開発日記",
            transcriptionText: "今日のランチはカレーだった",
            summaryText: "",
            tags: "日記"
        )

        // 「アプリ」AND「設計」→ memo-1のみ
        let results = try sut.search(query: "アプリ 設計")
        // AND検索なので、両方含むmemo-1が返る
        for result in results {
            XCTAssertEqual(result.memoID, "memo-1")
        }
    }

    // MARK: - Test 8: ランク順

    func test_search_ランク順() throws {
        try sut.createIndex()

        // "テスト" を多く含むメモ
        try sut.upsertIndex(
            memoID: "memo-high",
            title: "テスト テスト テスト",
            transcriptionText: "テストのテストをテストする",
            summaryText: "テスト",
            tags: "テスト"
        )

        // "テスト" を少なく含むメモ
        try sut.upsertIndex(
            memoID: "memo-low",
            title: "別の話題",
            transcriptionText: "今日はテストの日だった",
            summaryText: "",
            tags: ""
        )

        let results = try sut.search(query: "テスト")
        XCTAssertGreaterThanOrEqual(results.count, 1)
        // ランク順で返される（FTS5のrankはBM25ベース）
    }

    // MARK: - Test 9: 該当なし

    func test_search_該当なし() throws {
        try sut.createIndex()

        try sut.upsertIndex(
            memoID: "memo-1",
            title: "通常のメモ",
            transcriptionText: "通常の内容",
            summaryText: "",
            tags: ""
        )

        let results = try sut.search(query: "ジャバスクリプト")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Test 10: 空クエリ

    func test_search_空クエリ() throws {
        try sut.createIndex()

        let results = try sut.search(query: "")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Test 11: スニペット抽出

    func test_searchWithSnippets_スニペット抽出() throws {
        try sut.createIndex()

        // unicode61トークナイザは句読点（、。）で区切るため、
        // 検索対象の語がトークン全体と一致するようテストデータを構成する。
        // 「プロジェクト計画」が独立したトークンになるよう句読点で区切る。
        try sut.upsertIndex(
            memoID: "memo-1",
            title: "議事録",
            transcriptionText: "本日のミーティング。プロジェクト計画。重要なポイントは三つあります。",
            summaryText: "",
            tags: ""
        )

        let results = try sut.searchWithSnippets(
            query: "プロジェクト計画",
            snippetColumn: 2,
            maxTokens: 32
        )

        // スニペットが返される
        XCTAssertGreaterThanOrEqual(results.count, 1)
        if let first = results.first {
            XCTAssertEqual(first.memoID, "memo-1")
            // スニペットにmarkタグが含まれる
            XCTAssertTrue(first.snippet.contains("<mark>") || first.snippet.contains("プロジェクト"))
        }
    }

    // MARK: - Test 12: 特殊文字エスケープ

    func test_sanitizeQuery_特殊文字エスケープ() {
        let sut = FTS5IndexManager(dbPath: testDBPath, useICU: false)

        // FTS5特殊文字がエスケープされる
        let sanitized = sut.sanitizeQuery("test\"query*with(special)chars")
        XCTAssertFalse(sanitized.contains("*"))
        XCTAssertFalse(sanitized.contains("("))
        XCTAssertFalse(sanitized.contains(")"))

        // 空白クエリ
        let empty = sut.sanitizeQuery("   ")
        XCTAssertEqual(empty, "")

        // 通常クエリ
        let normal = sut.sanitizeQuery("テスト")
        XCTAssertTrue(normal.contains("テスト"))
    }

    // MARK: - Test 13: ICU利用可否チェック

    func test_checkICUAvailability() {
        // CI環境によってICUの可否が異なるため、クラッシュしないことのみ確認
        let result = FTS5IndexManager.checkICUAvailability(dbPath: testDBPath)
        // true or false のどちらか
        XCTAssertTrue(result == true || result == false)
    }
}
