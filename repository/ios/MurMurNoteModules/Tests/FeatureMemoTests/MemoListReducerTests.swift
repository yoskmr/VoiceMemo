import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

@MainActor
final class MemoListReducerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeMemoItem(
        id: UUID = UUID(),
        title: String = "テストメモ",
        createdAt: Date = Date(),
        durationSeconds: Double = 120,
        transcriptPreview: String = "テスト文字起こし...",
        emotion: EmotionCategory? = .joy,
        tags: [String] = ["テスト"],
        audioFilePath: String = "Audio/test.m4a"
    ) -> MemoListReducer.MemoItem {
        MemoListReducer.MemoItem(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            transcriptPreview: transcriptPreview,
            emotion: emotion,
            tags: tags,
            audioFilePath: audioFilePath
        )
    }

    private func makeEntity(
        id: UUID = UUID(),
        title: String = "テストメモ",
        createdAt: Date = Date(),
        durationSeconds: Double = 120,
        transcription: TranscriptionEntity? = nil,
        emotion: EmotionAnalysisEntity? = nil,
        tags: [TagEntity] = []
    ) -> VoiceMemoEntity {
        VoiceMemoEntity(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            audioFilePath: "Audio/test.m4a",
            transcription: transcription,
            emotionAnalysis: emotion,
            tags: tags
        )
    }

    // MARK: - Test 1: onAppear 空の状態で初回ロード

    func test_onAppear_空の状態で初回ロード() async {
        let now = Date()
        let memoID = UUID()

        let entity = makeEntity(
            id: memoID,
            title: "テストメモ1",
            createdAt: now,
            durationSeconds: 120,
            transcription: TranscriptionEntity(fullText: "テスト文字起こし..."),
            emotion: EmotionAnalysisEntity(primaryEmotion: .joy),
            tags: [TagEntity(name: "テスト")]
        )

        let store = TestStore(
            initialState: MemoListReducer.State()
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { _, _ in [entity] }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.memosLoaded.success) {
            $0.isLoading = false
            $0.currentPage = 1
            $0.hasMorePages = false
            $0.memos = IdentifiedArrayOf(uniqueElements: [
                MemoListReducer.MemoItem(
                    id: memoID,
                    title: "テストメモ1",
                    createdAt: now,
                    durationSeconds: 120,
                    transcriptPreview: "テスト文字起こし...",
                    emotion: .joy,
                    tags: ["テスト"],
                    audioFilePath: "Audio/test.m4a"
                )
            ])
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }
    }

    // MARK: - Test 2: 時系列降順ソート

    func test_memosLoaded_時系列降順ソート() async {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        let entities = [
            makeEntity(title: "古いメモ", createdAt: twoDaysAgo),
            makeEntity(title: "昨日のメモ", createdAt: yesterday),
            makeEntity(title: "今日のメモ", createdAt: now),
        ]

        let store = TestStore(
            initialState: MemoListReducer.State()
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { _, _ in entities }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.memosLoaded.success) {
            $0.isLoading = false
            $0.currentPage = 1
            $0.hasMorePages = false
            $0.memos = IdentifiedArrayOf(uniqueElements: entities.map { entity in
                MemoListReducer.MemoItem(
                    id: entity.id,
                    title: entity.title,
                    createdAt: entity.createdAt,
                    durationSeconds: entity.durationSeconds,
                    transcriptPreview: "",
                    emotion: nil,
                    tags: [],
                    audioFilePath: entity.audioFilePath
                )
            })
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }

        // セクションが新しい順であることを確認
        let sectionLabels = store.state.sections.map(\.label)
        XCTAssertEqual(sectionLabels.first, "今日")
    }

    // MARK: - Test 3: 日付セクション - 今日・昨日・それ以前

    func test_memosLoaded_日付セクション_今日_昨日_それ以前() async {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        let entities = [
            makeEntity(title: "今日", createdAt: now),
            makeEntity(title: "昨日", createdAt: yesterday),
            makeEntity(title: "先週", createdAt: lastWeek),
        ]

        let store = TestStore(
            initialState: MemoListReducer.State()
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { _, _ in entities }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memosLoaded.success) {
            $0.isLoading = false
            $0.currentPage = 1
            $0.hasMorePages = false
            $0.memos = IdentifiedArrayOf(uniqueElements: entities.map { entity in
                MemoListReducer.MemoItem(
                    id: entity.id,
                    title: entity.title,
                    createdAt: entity.createdAt,
                    durationSeconds: entity.durationSeconds,
                    transcriptPreview: "",
                    emotion: nil,
                    tags: [],
                    audioFilePath: entity.audioFilePath
                )
            })
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }

        let labels = store.state.sections.map(\.label)
        XCTAssertEqual(labels[0], "今日")
        XCTAssertEqual(labels[1], "昨日")
        // 3番目は日付表示
        XCTAssertTrue(labels[2].contains("年"))
    }

    // MARK: - Test 4: ページネーション

    func test_loadNextPage_ページネーション() async {
        let now = Date()

        // 50件のメモ（pageSize分） → hasMorePages = true
        let firstPage = (0..<50).map { i in
            makeEntity(title: "メモ\(i)", createdAt: now)
        }
        let secondPage = [makeEntity(title: "メモ50", createdAt: now)]

        var fetchCallCount = 0
        let store = TestStore(
            initialState: MemoListReducer.State()
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { page, _ in
                fetchCallCount += 1
                if page == 0 { return firstPage }
                return secondPage
            }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        // 初回ロード
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memosLoaded.success) {
            $0.isLoading = false
            $0.currentPage = 1
            $0.hasMorePages = true  // 50件 == pageSize → まだあるかも
            $0.memos = IdentifiedArrayOf(uniqueElements: firstPage.map { entity in
                MemoListReducer.MemoItem(
                    id: entity.id,
                    title: entity.title,
                    createdAt: entity.createdAt,
                    durationSeconds: entity.durationSeconds,
                    transcriptPreview: "",
                    emotion: nil,
                    tags: [],
                    audioFilePath: entity.audioFilePath
                )
            })
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }

        // 次のページ
        await store.send(.loadNextPage) { $0.isLoading = true }
        await store.receive(\.memosLoaded.success) {
            $0.isLoading = false
            $0.currentPage = 2
            $0.hasMorePages = false  // 1件 < pageSize → もうない
            // 51件目追加
            let newItem = MemoListReducer.MemoItem(
                id: secondPage[0].id,
                title: "メモ50",
                createdAt: now,
                durationSeconds: 120,
                transcriptPreview: "",
                emotion: nil,
                tags: [],
                audioFilePath: "Audio/test.m4a"
            )
            $0.memos.updateOrAppend(newItem)
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }

        XCTAssertEqual(fetchCallCount, 2)
    }

    // MARK: - Test 5: 全件読み込み済みで追加ロードしない

    func test_loadNextPage_全件読み込み済みで追加ロードしない() async {
        let store = TestStore(
            initialState: MemoListReducer.State(hasMorePages: false)
        ) {
            MemoListReducer()
        }

        await store.send(.loadNextPage)
        // アクションが処理されないこと（state変更なし）を確認
    }

    // MARK: - Test 6: ロード中に重複リクエストしない

    func test_loadNextPage_ロード中に重複リクエストしない() async {
        let store = TestStore(
            initialState: MemoListReducer.State(isLoading: true)
        ) {
            MemoListReducer()
        }

        await store.send(.loadNextPage)
        // isLoading中は何もしない
    }

    // MARK: - Test 7: スワイプ削除アクション伝播

    func test_swipeToDelete_削除アクション伝播() async {
        let memoID = UUID()
        let now = Date()

        let store = TestStore(
            initialState: MemoListReducer.State(
                memos: IdentifiedArrayOf(uniqueElements: [
                    makeMemoItem(id: memoID, createdAt: now)
                ]),
                sections: MemoListReducer.buildSections(
                    from: IdentifiedArrayOf(uniqueElements: [
                        makeMemoItem(id: memoID, createdAt: now)
                    ]),
                    now: now,
                    calendar: Calendar.current
                )
            )
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.delete = { _ in }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.swipeToDelete(id: memoID))

        await store.receive(.deleteConfirmed(id: memoID))

        await store.receive(\.memoDeleted.success) {
            $0.memos = []
            $0.sections = []
        }
    }

    // MARK: - Test 8: プルリフレッシュ

    func test_refreshRequested_プルリフレッシュ() async {
        let now = Date()
        let existingMemo = makeMemoItem(title: "古いメモ", createdAt: now)
        let freshMemo = makeEntity(title: "新しいメモ", createdAt: now)

        let store = TestStore(
            initialState: MemoListReducer.State(
                memos: IdentifiedArrayOf(uniqueElements: [existingMemo]),
                currentPage: 1
            )
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { _, _ in [freshMemo] }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.refreshRequested) {
            $0.isLoading = true
            $0.currentPage = 0
        }

        await store.receive(\.refreshCompleted.success) {
            $0.isLoading = false
            $0.currentPage = 1
            $0.hasMorePages = false
            $0.memos = IdentifiedArrayOf(uniqueElements: [
                MemoListReducer.MemoItem(
                    id: freshMemo.id,
                    title: "新しいメモ",
                    createdAt: now,
                    durationSeconds: 120,
                    transcriptPreview: "",
                    emotion: nil,
                    tags: [],
                    audioFilePath: "Audio/test.m4a"
                )
            ])
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }
    }

    // MARK: - Test 9: エラーメッセージ表示

    func test_memosLoaded_failure_エラーメッセージ表示() async {
        let store = TestStore(
            initialState: MemoListReducer.State()
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { _, _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "テストエラー"])
            }
            $0.date.now = Date()
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.memosLoaded.failure) {
            $0.isLoading = false
            $0.errorMessage = "テストエラー"
        }
    }

    // MARK: - Test 10: 空配列で空セクション

    func test_buildSections_空配列で空セクション() {
        let sections = MemoListReducer.buildSections(
            from: [],
            now: Date(),
            calendar: Calendar.current
        )
        XCTAssertTrue(sections.isEmpty)
    }
}
