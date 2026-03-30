import ComposableArchitecture
import XCTest
@testable import Domain
@testable import FeatureSearch

@MainActor
final class SearchReducerTests: XCTestCase {

    private let testDate = Date(timeIntervalSince1970: 1700000000)
    private let testMemoID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // MARK: - Test 1: searchTextChanged で 300msデバウンス

    func test_searchTextChanged_300msデバウンス() async {
        let clock = TestClock()
        var searchCalled = false

        let store = TestStore(
            initialState: SearchReducer.State()
        ) {
            SearchReducer()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = Date()
            $0.calendar = Calendar.current
            $0.fts5IndexManager.searchWithSnippets = { _, _, _ in
                searchCalled = true
                return [
                    FTS5SearchResult(
                        memoID: "00000000-0000-0000-0000-000000000001",
                        snippet: "テスト<mark>アイデア</mark>メモ",
                        rank: -1.0
                    ),
                ]
            }
            $0.voiceMemoRepository.fetchMemosByIDs = { ids in
                var result: [UUID: SearchableMemo] = [:]
                for id in ids {
                    result[id] = SearchableMemo(
                        title: "テスト",
                        createdAt: Date(timeIntervalSince1970: 1700000000),
                        emotion: .joy,
                        durationSeconds: 120,
                        tags: ["アイデア"]
                    )
                }
                return result
            }
        }

        await store.send(.searchTextChanged("アイデア")) {
            $0.searchText = "アイデア"
            $0.isInitialState = false
        }

        // 300ms前は検索が実行されていない
        await clock.advance(by: .milliseconds(200))
        XCTAssertFalse(searchCalled)

        // 300ms経過で検索実行
        await clock.advance(by: .milliseconds(100))

        await store.receive(.performSearch) {
            $0.isSearching = true
        }

        await store.receive(.searchCompleted(.success([
            SearchReducer.SearchResultItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "テスト",
                snippet: "テスト<mark>アイデア</mark>メモ",
                createdAt: Date(timeIntervalSince1970: 1700000000),
                emotion: .joy,
                durationSeconds: 120,
                tags: ["アイデア"]
            ),
        ]))) {
            $0.isSearching = false
            $0.resultCount = 1
            $0.results = [
                SearchReducer.SearchResultItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    title: "テスト",
                    snippet: "テスト<mark>アイデア</mark>メモ",
                    createdAt: Date(timeIntervalSince1970: 1700000000),
                    emotion: .joy,
                    durationSeconds: 120,
                    tags: ["アイデア"]
                ),
            ]
        }
    }

    // MARK: - Test 2: 連続入力でデバウンスリセット

    func test_searchTextChanged_連続入力でデバウンスリセット() async {
        let clock = TestClock()
        var searchCount = 0

        let store = TestStore(
            initialState: SearchReducer.State()
        ) {
            SearchReducer()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = Date()
            $0.calendar = Calendar.current
            $0.fts5IndexManager.searchWithSnippets = { _, _, _ in
                searchCount += 1
                return []
            }
        }

        // 1回目の入力
        await store.send(.searchTextChanged("テスト")) {
            $0.searchText = "テスト"
            $0.isInitialState = false
        }

        // 200ms後に2回目の入力（デバウンスリセット）
        await clock.advance(by: .milliseconds(200))

        await store.send(.searchTextChanged("テスト2")) {
            $0.searchText = "テスト2"
        }

        // さらに300ms後に1回だけ検索
        await clock.advance(by: .milliseconds(300))

        await store.receive(.performSearch) {
            $0.isSearching = true
        }

        await store.receive(.searchCompleted(.success([]))) {
            $0.isSearching = false
            $0.resultCount = 0
        }

        XCTAssertEqual(searchCount, 1)
    }

    // MARK: - Test 3: 空文字で結果クリア

    func test_searchTextChanged_空文字で結果クリア() async {
        let store = TestStore(
            initialState: SearchReducer.State(
                searchText: "テスト",
                results: [
                    SearchReducer.SearchResultItem(
                        id: UUID(),
                        title: "テスト",
                        snippet: "スニペット",
                        createdAt: Date(),
                        emotion: nil,
                        durationSeconds: 60,
                        tags: []
                    ),
                ],
                resultCount: 1
            )
        ) {
            SearchReducer()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.searchTextChanged("")) {
            $0.searchText = ""
            $0.isInitialState = false
            $0.results = []
            $0.resultCount = 0
        }
    }

    // MARK: - Test 4: 検索失敗でエラー表示

    func test_performSearch_failure_エラー表示() async {
        let store = TestStore(
            initialState: SearchReducer.State(
                searchText: "テスト"
            )
        ) {
            SearchReducer()
        } withDependencies: {
            $0.date.now = Date()
            $0.calendar = Calendar.current
            $0.fts5IndexManager.searchWithSnippets = { _, _, _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "検索エラー"])
            }
        }

        await store.send(.performSearch) {
            $0.isSearching = true
        }

        await store.receive(.searchCompleted(.failure("検索エラー"))) {
            $0.isSearching = false
            $0.errorMessage = "検索エラー"
        }
    }

    // MARK: - Test 5: toggleFilters

    func test_toggleFilters() async {
        let store = TestStore(
            initialState: SearchReducer.State()
        ) {
            SearchReducer()
        }

        await store.send(.toggleFilters) {
            $0.showFilters = true
        }

        await store.send(.toggleFilters) {
            $0.showFilters = false
        }
    }

    // MARK: - Test 6: dateFilterChanged でフィルター適用後に再検索

    func test_dateFilterChanged_フィルター適用後に再検索() async {
        let store = TestStore(
            initialState: SearchReducer.State(
                searchText: "テスト"
            )
        ) {
            SearchReducer()
        } withDependencies: {
            $0.date.now = Date()
            $0.calendar = Calendar.current
            $0.fts5IndexManager.searchWithSnippets = { _, _, _ in [] }
        }

        await store.send(.dateFilterChanged(.week)) {
            $0.selectedDateFilter = .week
        }

        await store.receive(.performSearch) {
            $0.isSearching = true
        }

        await store.receive(.searchCompleted(.success([]))) {
            $0.isSearching = false
            $0.resultCount = 0
        }
    }

    // MARK: - Test 7: tagFilterToggled でタグ選択/解除

    func test_tagFilterToggled_タグ選択解除() async {
        let store = TestStore(
            initialState: SearchReducer.State(
                searchText: "テスト"
            )
        ) {
            SearchReducer()
        } withDependencies: {
            $0.date.now = Date()
            $0.calendar = Calendar.current
            $0.fts5IndexManager.searchWithSnippets = { _, _, _ in [] }
        }

        // タグ選択
        await store.send(.tagFilterToggled("アイデア")) {
            $0.selectedTags = ["アイデア"]
        }

        await store.receive(.performSearch) {
            $0.isSearching = true
        }
        await store.receive(.searchCompleted(.success([]))) {
            $0.isSearching = false
            $0.resultCount = 0
        }

        // タグ解除
        await store.send(.tagFilterToggled("アイデア")) {
            $0.selectedTags = []
        }

        await store.receive(.performSearch) {
            $0.isSearching = true
        }
        await store.receive(.searchCompleted(.success([]))) {
            $0.isSearching = false
        }
    }

    // MARK: - Test 8: clearFilters で全フィルターリセット

    func test_clearFilters_全フィルターリセット() async {
        let store = TestStore(
            initialState: SearchReducer.State(
                searchText: "テスト",
                selectedDateFilter: .week,
                selectedTags: ["アイデア", "仕事"]
            )
        ) {
            SearchReducer()
        } withDependencies: {
            $0.date.now = Date()
            $0.calendar = Calendar.current
            $0.fts5IndexManager.searchWithSnippets = { _, _, _ in [] }
        }

        await store.send(.clearFilters) {
            $0.selectedDateFilter = .all
            $0.selectedTags = []
        }

        await store.receive(.performSearch) {
            $0.isSearching = true
        }
        await store.receive(.searchCompleted(.success([]))) {
            $0.isSearching = false
            $0.resultCount = 0
        }
    }

    // MARK: - Test 9: onAppear でタグ一覧ロード

    func test_onAppear_タグ一覧ロード() async {
        let store = TestStore(
            initialState: SearchReducer.State()
        ) {
            SearchReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAllTags = {
                ["アイデア", "仕事", "日記"]
            }
        }

        await store.send(.onAppear)

        await store.receive(.availableTagsLoaded(["アイデア", "仕事", "日記"])) {
            $0.availableTags = ["アイデア", "仕事", "日記"]
        }
    }

    // MARK: - Test 10: resultTapped でアクション伝播

    func test_resultTapped_アクション伝播() async {
        let memoID = UUID()
        let store = TestStore(
            initialState: SearchReducer.State()
        ) {
            SearchReducer()
        }

        await store.send(.resultTapped(id: memoID))
    }
}
