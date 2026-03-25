import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

@MainActor
final class EmotionTrendReducerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeEntity(
        id: UUID = UUID(),
        title: String = "テストメモ",
        createdAt: Date = Date(),
        durationSeconds: Double = 120,
        emotionAnalysis: EmotionAnalysisEntity? = nil
    ) -> VoiceMemoEntity {
        VoiceMemoEntity(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            audioFilePath: "Audio/test.m4a",
            emotionAnalysis: emotionAnalysis
        )
    }

    // MARK: - Test 1: onAppear で感情データなしの場合は空配列

    func test_onAppear_感情データなしの場合は空配列() async {
        let memoWithoutEmotion = makeEntity(title: "メモ1")

        let store = TestStore(
            initialState: EmotionTrendReducer.State()
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { [memoWithoutEmotion] }
            $0.date.now = Date()
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            $0.emotions = []
        }
    }

    // MARK: - Test 2: onAppear で感情データありの場合はエントリを返す

    func test_onAppear_感情データありの場合はエントリを返す() async {
        let memoID = UUID()
        let now = Date()
        let analysis = EmotionAnalysisEntity(
            primaryEmotion: .joy,
            confidence: 0.85,
            analyzedAt: now
        )
        let memoWithEmotion = makeEntity(
            id: memoID,
            title: "楽しいメモ",
            createdAt: now,
            emotionAnalysis: analysis
        )

        let store = TestStore(
            initialState: EmotionTrendReducer.State()
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { [memoWithEmotion] }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            $0.emotions = [
                EmotionTrendReducer.EmotionEntry(
                    id: memoID,
                    date: now,
                    primaryEmotion: .joy,
                    confidence: 0.85,
                    memoTitle: "楽しいメモ"
                ),
            ]
        }
    }

    // MARK: - Test 3: confidence が 0 のエントリは除外

    func test_onAppear_confidenceが0のエントリは除外() async {
        let analysis = EmotionAnalysisEntity(
            primaryEmotion: .neutral,
            confidence: 0.0
        )
        let memo = makeEntity(title: "未分析メモ", emotionAnalysis: analysis)

        let store = TestStore(
            initialState: EmotionTrendReducer.State()
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { [memo] }
            $0.date.now = Date()
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            $0.emotions = []
        }
    }

    // MARK: - Test 4: periodChanged で期間フィルタリング

    func test_periodChanged_期間フィルタリング() async {
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let memoID = UUID()

        let recentAnalysis = EmotionAnalysisEntity(
            primaryEmotion: .calm,
            confidence: 0.9,
            analyzedAt: now
        )
        let recentMemo = makeEntity(
            id: memoID,
            title: "最近のメモ",
            createdAt: now,
            emotionAnalysis: recentAnalysis
        )

        let oldAnalysis = EmotionAnalysisEntity(
            primaryEmotion: .sadness,
            confidence: 0.7,
            analyzedAt: twoWeeksAgo
        )
        let oldMemo = makeEntity(
            title: "古いメモ",
            createdAt: twoWeeksAgo,
            emotionAnalysis: oldAnalysis
        )

        let store = TestStore(
            initialState: EmotionTrendReducer.State(selectedPeriod: .all)
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { [recentMemo, oldMemo] }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        // 1週間に変更 → 古いメモは除外される
        await store.send(.periodChanged(.week)) {
            $0.selectedPeriod = .week
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            $0.emotions = [
                EmotionTrendReducer.EmotionEntry(
                    id: memoID,
                    date: now,
                    primaryEmotion: .calm,
                    confidence: 0.9,
                    memoTitle: "最近のメモ"
                ),
            ]
        }
    }

    // MARK: - Test 5: emotionsLoaded failure でエラーハンドリング

    func test_emotionsLoaded_failure_エラーハンドリング() async {
        let store = TestStore(
            initialState: EmotionTrendReducer.State()
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = {
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "テストエラー"])
            }
            $0.date.now = Date()
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.failure) {
            $0.isLoading = false
            $0.emotions = []
        }
    }

    // MARK: - Test 6: 結果が新しい順にソートされる

    func test_onAppear_結果が新しい順にソート() async {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let memoID1 = UUID()
        let memoID2 = UUID()

        let analysis1 = EmotionAnalysisEntity(primaryEmotion: .joy, confidence: 0.8, analyzedAt: yesterday)
        let memo1 = makeEntity(id: memoID1, title: "昨日のメモ", createdAt: yesterday, emotionAnalysis: analysis1)

        let analysis2 = EmotionAnalysisEntity(primaryEmotion: .calm, confidence: 0.9, analyzedAt: now)
        let memo2 = makeEntity(id: memoID2, title: "今日のメモ", createdAt: now, emotionAnalysis: analysis2)

        let store = TestStore(
            initialState: EmotionTrendReducer.State(selectedPeriod: .all)
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            // 古い順で渡す
            $0.voiceMemoRepository.fetchAll = { [memo1, memo2] }
            $0.date.now = now
            $0.calendar = Calendar.current
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            // 新しい順にソートされている
            $0.emotions = [
                EmotionTrendReducer.EmotionEntry(
                    id: memoID2,
                    date: now,
                    primaryEmotion: .calm,
                    confidence: 0.9,
                    memoTitle: "今日のメモ"
                ),
                EmotionTrendReducer.EmotionEntry(
                    id: memoID1,
                    date: yesterday,
                    primaryEmotion: .joy,
                    confidence: 0.8,
                    memoTitle: "昨日のメモ"
                ),
            ]
        }
    }
}
