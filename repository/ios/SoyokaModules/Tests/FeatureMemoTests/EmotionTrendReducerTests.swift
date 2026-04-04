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
            $0.subscriptionClient.currentSubscription = { .free }
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

        // dailyEmotions は初期値が [] なので変化なし（感情データなしのため空配列）
        await store.receive(\.dailyEmotionsLoaded) {
            XCTAssertTrue($0.dailyEmotions.isEmpty)
        }

        // subscriptionStateLoaded: isPro = false（Free プラン）
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertFalse($0.isPro)
        }
    }

    // MARK: - Test 2: onAppear で感情データありの場合はエントリを返す

    func test_onAppear_感情データありの場合はエントリを返す() async {
        let memoID = UUID()
        let now = Date()
        let calendar = Calendar.current
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
            $0.subscriptionClient.currentSubscription = { .free }
            $0.date.now = now
            $0.calendar = calendar
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

        let dayStart = calendar.startOfDay(for: now)
        await store.receive(\.dailyEmotionsLoaded) {
            $0.dailyEmotions = [
                EmotionTrendReducer.DailyEmotion(
                    date: dayStart,
                    emotions: [.joy: 0.85],
                    memoCount: 1
                ),
            ]
        }

        // subscriptionStateLoaded: isPro = false（Free プラン）
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertFalse($0.isPro)
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
            $0.subscriptionClient.currentSubscription = { .free }
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

        // confidence == 0 のエントリは除外されるため dailyEmotions も空
        await store.receive(\.dailyEmotionsLoaded) {
            XCTAssertTrue($0.dailyEmotions.isEmpty)
        }

        // subscriptionStateLoaded: isPro = false（Free プラン）
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertFalse($0.isPro)
        }
    }

    // MARK: - Test 4: periodChanged で期間フィルタリング

    func test_periodChanged_期間フィルタリング() async {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!
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
            $0.subscriptionClient.currentSubscription = { .free }
            $0.date.now = now
            $0.calendar = calendar
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

        let dayStart = calendar.startOfDay(for: now)
        await store.receive(\.dailyEmotionsLoaded) {
            $0.dailyEmotions = [
                EmotionTrendReducer.DailyEmotion(
                    date: dayStart,
                    emotions: [.calm: 0.9],
                    memoCount: 1
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
            $0.subscriptionClient.currentSubscription = { .free }
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

        // fetchAll が失敗しても aggregateDailyEmotions は空配列を返す
        await store.receive(\.dailyEmotionsLoaded) {
            XCTAssertTrue($0.dailyEmotions.isEmpty)
        }

        // subscriptionStateLoaded: isPro = false（Free プラン）
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertFalse($0.isPro)
        }
    }

    // MARK: - Test 6: 結果が新しい順にソートされる

    func test_onAppear_結果が新しい順にソート() async {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
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
            $0.subscriptionClient.currentSubscription = { .free }
            $0.date.now = now
            $0.calendar = calendar
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            // 新しい順にソートされている（Free: 3件以下なので全件表示）
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

        let yesterdayStart = calendar.startOfDay(for: yesterday)
        let todayStart = calendar.startOfDay(for: now)
        await store.receive(\.dailyEmotionsLoaded) {
            // 日付昇順でソートされている
            $0.dailyEmotions = [
                EmotionTrendReducer.DailyEmotion(
                    date: yesterdayStart,
                    emotions: [.joy: 0.8],
                    memoCount: 1
                ),
                EmotionTrendReducer.DailyEmotion(
                    date: todayStart,
                    emotions: [.calm: 0.9],
                    memoCount: 1
                ),
            ]
        }

        // subscriptionStateLoaded: isPro = false（Free プラン）
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertFalse($0.isPro)
        }
    }

    // MARK: - Test 7: quarter 期間フィルタリング（TASK-0042）

    func test_quarter_期間フィルタリング() async {
        let now = Date()
        let calendar = Calendar.current
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let fourMonthsAgo = calendar.date(byAdding: .month, value: -4, to: now)!
        let recentMemoID = UUID()
        let twoMonthMemoID = UUID()

        let recentAnalysis = EmotionAnalysisEntity(primaryEmotion: .joy, confidence: 0.9, analyzedAt: now)
        let recentMemo = makeEntity(id: recentMemoID, title: "最近のメモ", createdAt: now, emotionAnalysis: recentAnalysis)

        let twoMonthAnalysis = EmotionAnalysisEntity(primaryEmotion: .calm, confidence: 0.8, analyzedAt: twoMonthsAgo)
        let twoMonthMemo = makeEntity(id: twoMonthMemoID, title: "2ヶ月前のメモ", createdAt: twoMonthsAgo, emotionAnalysis: twoMonthAnalysis)

        let fourMonthAnalysis = EmotionAnalysisEntity(primaryEmotion: .sadness, confidence: 0.7, analyzedAt: fourMonthsAgo)
        let fourMonthMemo = makeEntity(title: "4ヶ月前のメモ", createdAt: fourMonthsAgo, emotionAnalysis: fourMonthAnalysis)

        let store = TestStore(
            initialState: EmotionTrendReducer.State(selectedPeriod: .all, isPro: true)
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { [recentMemo, twoMonthMemo, fourMonthMemo] }
            $0.subscriptionClient.currentSubscription = { .pro(expiresAt: Date.distantFuture) }
            $0.date.now = now
            $0.calendar = calendar
        }

        // 3ヶ月に変更 → 4ヶ月前のメモは除外される
        await store.send(.periodChanged(.quarter)) {
            $0.selectedPeriod = .quarter
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            // 新しい順: 最近 → 2ヶ月前（4ヶ月前は除外）
            $0.emotions = [
                EmotionTrendReducer.EmotionEntry(
                    id: recentMemoID,
                    date: now,
                    primaryEmotion: .joy,
                    confidence: 0.9,
                    memoTitle: "最近のメモ"
                ),
                EmotionTrendReducer.EmotionEntry(
                    id: twoMonthMemoID,
                    date: twoMonthsAgo,
                    primaryEmotion: .calm,
                    confidence: 0.8,
                    memoTitle: "2ヶ月前のメモ"
                ),
            ]
        }

        let todayStart = calendar.startOfDay(for: now)
        let twoMonthStart = calendar.startOfDay(for: twoMonthsAgo)
        await store.receive(\.dailyEmotionsLoaded) {
            $0.dailyEmotions = [
                EmotionTrendReducer.DailyEmotion(
                    date: twoMonthStart,
                    emotions: [.calm: 0.8],
                    memoCount: 1
                ),
                EmotionTrendReducer.DailyEmotion(
                    date: todayStart,
                    emotions: [.joy: 0.9],
                    memoCount: 1
                ),
            ]
        }
    }

    // MARK: - Test 8: Free ユーザーは最新3件のみ取得（TASK-0042）

    func test_free_最新3件のみ取得() async {
        let now = Date()
        let calendar = Calendar.current
        let ids = (0..<5).map { _ in UUID() }
        let memos = ids.enumerated().map { index, id -> VoiceMemoEntity in
            let date = calendar.date(byAdding: .hour, value: -index, to: now)!
            let analysis = EmotionAnalysisEntity(
                primaryEmotion: .joy,
                confidence: Double(5 - index) * 0.1 + 0.5,
                analyzedAt: date
            )
            return makeEntity(id: id, title: "メモ\(index)", createdAt: date, emotionAnalysis: analysis)
        }

        let store = TestStore(
            initialState: EmotionTrendReducer.State(selectedPeriod: .all, isPro: false)
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { memos }
            $0.subscriptionClient.currentSubscription = { .free }
            $0.date.now = now
            $0.calendar = calendar
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            // Free: 最新3件のみ（全5件のうち上位3件）
            XCTAssertEqual($0.emotions.count, 3)
            XCTAssertEqual($0.emotions[0].id, ids[0])
            XCTAssertEqual($0.emotions[1].id, ids[1])
            XCTAssertEqual($0.emotions[2].id, ids[2])
        }

        let dayStart = calendar.startOfDay(for: now)
        await store.receive(\.dailyEmotionsLoaded) {
            // dailyEmotions は全データが集計される（チャート描画用、Free制限なし）
            // 5件すべて同日・.joy なので1つの DailyEmotion に集約される
            XCTAssertEqual($0.dailyEmotions.count, 1)
            let daily = $0.dailyEmotions[0]
            XCTAssertEqual(daily.date, dayStart)
            XCTAssertEqual(daily.memoCount, 5)
            XCTAssertNotNil(daily.emotions[.joy])
            // joy のスコア合計: 1.0 + 0.9 + 0.8 + 0.7 + 0.6 = 4.0
            XCTAssertEqual(daily.emotions[.joy]!, 4.0, accuracy: 0.01)
            $0.dailyEmotions = $0.dailyEmotions
        }

        // subscriptionStateLoaded: isPro = false（Free プラン、初期値と同じため状態変化なし）
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertFalse($0.isPro)
        }
    }

    // MARK: - Test 9: Pro ユーザーは全件取得（TASK-0042）

    func test_pro_全件取得() async {
        let now = Date()
        let calendar = Calendar.current
        let ids = (0..<5).map { _ in UUID() }
        let memos = ids.enumerated().map { index, id -> VoiceMemoEntity in
            let date = calendar.date(byAdding: .hour, value: -index, to: now)!
            let analysis = EmotionAnalysisEntity(
                primaryEmotion: .joy,
                confidence: Double(5 - index) * 0.1 + 0.5,
                analyzedAt: date
            )
            return makeEntity(id: id, title: "メモ\(index)", createdAt: date, emotionAnalysis: analysis)
        }

        let store = TestStore(
            initialState: EmotionTrendReducer.State(selectedPeriod: .all, isPro: true)
        ) {
            EmotionTrendReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchAll = { memos }
            $0.subscriptionClient.currentSubscription = { .pro(expiresAt: Date.distantFuture) }
            $0.date.now = now
            $0.calendar = calendar
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.emotionsLoaded.success) {
            $0.isLoading = false
            // Pro: 全5件取得
            XCTAssertEqual($0.emotions.count, 5)
            XCTAssertEqual($0.emotions[0].id, ids[0])
            XCTAssertEqual($0.emotions[4].id, ids[4])
        }

        let dayStart = calendar.startOfDay(for: now)
        await store.receive(\.dailyEmotionsLoaded) {
            // 5件すべて同日・.joy なので1つの DailyEmotion に集約される
            XCTAssertEqual($0.dailyEmotions.count, 1)
            let daily = $0.dailyEmotions[0]
            XCTAssertEqual(daily.date, dayStart)
            XCTAssertEqual(daily.memoCount, 5)
            XCTAssertNotNil(daily.emotions[.joy])
            // joy のスコア合計: 1.0 + 0.9 + 0.8 + 0.7 + 0.6 = 4.0
            XCTAssertEqual(daily.emotions[.joy]!, 4.0, accuracy: 0.01)
            $0.dailyEmotions = $0.dailyEmotions
        }

        // isPro は初期値 true → subscriptionStateLoaded(true) で変化なし
        await store.receive(\.subscriptionStateLoaded) {
            XCTAssertTrue($0.isPro)
        }
    }
}
