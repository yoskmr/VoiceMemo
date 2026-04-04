import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

/// T16: エンドツーエンドインテグレーションテスト
/// 録音完了 → AI処理トリガー → ステータス変化 → リロード → 要約表示の全フロー
/// モックLLMを使用（固定レスポンス）
@MainActor
final class MemoDetailAIIntegrationTests: XCTestCase {

    private let testMemoID = UUID()
    private let testDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let testResetDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Test 1: AI処理トリガー → ステータス変化 → 完了 → リロード → 要約表示

    func test_AIフルフロー_トリガーから要約表示まで() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        // 初期メモ（AI要約なし）
        let initialEntity = makeEntity(
            transcription: TranscriptionEntity(
                fullText: "今日は会議があって色々と議論しました。プロジェクトの進捗確認と今後の方針について話し合いました。",
                language: "ja-JP",
                confidence: 0.95
            ),
            aiSummary: nil,
            tags: []
        )

        // AI処理完了後のメモ（AI要約あり）
        let summaryDate = Date(timeIntervalSince1970: 1_700_000_200)
        let processedEntity = makeEntity(
            transcription: TranscriptionEntity(
                fullText: "今日は会議があって色々と議論しました。プロジェクトの進捗確認と今後の方針について話し合いました。",
                language: "ja-JP",
                confidence: 0.95
            ),
            aiSummary: AISummaryEntity(
                summaryText: "会議での進捗確認と方針検討のまとめ",
                keyPoints: ["進捗確認", "方針検討"],
                providerType: .onDeviceLlamaCpp,
                isOnDevice: true,
                generatedAt: summaryDate
            ),
            tags: [
                TagEntity(id: UUID(), name: "会議", source: .ai),
                TagEntity(id: UUID(), name: "進捗", source: .ai),
            ]
        )

        let fetchCallCount = LockIsolated(0)
        let enqueuedMemoID = LockIsolated<UUID?>(nil)

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in
                fetchCallCount.withValue { $0 += 1 }
                // 初回ロード時は AI要約なし、2回目以降は AI要約あり
                if fetchCallCount.value <= 1 {
                    return initialEntity
                } else {
                    return processedEntity
                }
            }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
            $0.aiProcessingQueue.enqueueProcessing = { id in
                enqueuedMemoID.withValue { $0 = id }
            }
            $0.aiQuota.remainingCount = { 14 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + quotaInfoLoaded）と
        // AI処理完了時の並行エフェクト（memoLoaded + quotaInfoLoaded）の順序が非決定的なため
        store.exhaustivity = .off

        // 1. メモ詳細ロード
        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.transcriptionText = "今日は会議があって色々と議論しました。プロジェクトの進捗確認と今後の方針について話し合いました。"
            $0.aiSummary = nil
            $0.isAISummaryAvailable = false
        }

        // AI要約がまだないことを確認
        XCTAssertNil(store.state.aiSummary)
        XCTAssertFalse(store.state.isAISummaryAvailable)

        // 2. AI処理をトリガー
        await store.send(.triggerAIProcessing) {
            $0.aiProcessingStatus = .queued
        }

        XCTAssertEqual(enqueuedMemoID.value, testMemoID)

        // 3. AI処理完了ステータスを受信
        await store.send(.aiProcessingStatusUpdated(.completed(isOnDevice: true))) {
            $0.aiProcessingStatus = .completed(isOnDevice: true)
        }

        // 4. 完了後にメモ詳細をリロード → AI要約が表示される
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.aiSummary = MemoDetailReducer.State.AISummaryState(
                summaryText: "会議での進捗確認と方針検討のまとめ",
                keyPoints: ["進捗確認", "方針検討"],
                providerType: "on_device_llama_cpp",
                isOnDevice: true,
                generatedAt: summaryDate
            )
            $0.isAISummaryAvailable = true
            $0.tags = processedEntity.tags.map {
                MemoDetailReducer.State.TagItem(
                    id: $0.id,
                    name: $0.name,
                    source: $0.source.rawValue
                )
            }
        }

        XCTAssertNotNil(store.state.aiSummary)
        XCTAssertTrue(store.state.isAISummaryAvailable)
        XCTAssertEqual(store.state.tags.count, 2)
    }

    // MARK: - Test 2: 月上限到達シナリオ

    func test_AI処理_月上限到達_quotaExceeded表示() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let initialEntity = makeEntity(
            transcription: TranscriptionEntity(
                fullText: "テスト用のメモテキストです。",
                language: "ja-JP",
                confidence: 0.9
            )
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in initialEntity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
            $0.aiProcessingQueue.enqueueProcessing = { _ in }
            $0.aiQuota.remainingCount = { 0 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + quotaInfoLoaded）の順序が非決定的なため
        store.exhaustivity = .off

        // メモ詳細ロード
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success)

        // AI処理トリガー
        await store.send(.triggerAIProcessing) {
            $0.aiProcessingStatus = .queued
        }

        // キューは追加されるが、AIProcessingQueueLive 内部でquota超過が検出される
        // ここではステータス通知をシミュレート
        await store.send(.aiProcessingStatusUpdated(
            .failed(.quotaExceeded(remaining: 0, resetDate: testResetDate))
        )) {
            $0.aiProcessingStatus = .failed(.quotaExceeded(remaining: 0, resetDate: self.testResetDate))
        }

        // AI要約は生成されないことを確認
        XCTAssertNil(store.state.aiSummary)
        XCTAssertFalse(store.state.isAISummaryAvailable)
    }

    // MARK: - Test 3: regenerateAISummary → 再生成

    func test_AI再生成_既存要約がある状態から再生成() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let summaryDate = Date(timeIntervalSince1970: 1_700_000_100)
        let initialEntity = makeEntity(
            transcription: TranscriptionEntity(
                fullText: "以前のメモテキスト。再分析対象です。",
                language: "ja-JP",
                confidence: 0.9
            ),
            aiSummary: AISummaryEntity(
                summaryText: "古い要約",
                keyPoints: [],
                providerType: .onDeviceLlamaCpp,
                isOnDevice: true,
                generatedAt: summaryDate
            )
        )

        let newSummaryDate = Date(timeIntervalSince1970: 1_700_001_000)
        let regeneratedEntity = makeEntity(
            transcription: TranscriptionEntity(
                fullText: "以前のメモテキスト。再分析対象です。",
                language: "ja-JP",
                confidence: 0.9
            ),
            aiSummary: AISummaryEntity(
                summaryText: "新しい要約（再生成）",
                keyPoints: ["新ポイント"],
                providerType: .onDeviceLlamaCpp,
                isOnDevice: true,
                generatedAt: newSummaryDate
            )
        )

        let fetchCallCount = LockIsolated(0)
        let enqueuedMemoID = LockIsolated<UUID?>(nil)

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in
                fetchCallCount.withValue { $0 += 1 }
                if fetchCallCount.value <= 1 {
                    return initialEntity
                } else {
                    return regeneratedEntity
                }
            }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
            $0.aiProcessingQueue.enqueueProcessing = { id in
                enqueuedMemoID.withValue { $0 = id }
            }
            $0.aiQuota.remainingCount = { 13 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + quotaInfoLoaded）と
        // AI処理完了時の並行エフェクト（memoLoaded + quotaInfoLoaded）の順序が非決定的なため
        store.exhaustivity = .off

        // 初回ロード
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.aiSummary = MemoDetailReducer.State.AISummaryState(
                summaryText: "古い要約",
                keyPoints: [],
                providerType: "on_device_llama_cpp",
                isOnDevice: true,
                generatedAt: summaryDate
            )
            $0.isAISummaryAvailable = true
        }

        // 再生成トリガー
        await store.send(.regenerateAISummary) {
            $0.aiProcessingStatus = .queued
        }
        XCTAssertEqual(enqueuedMemoID.value, testMemoID)

        // AI処理完了
        await store.send(.aiProcessingStatusUpdated(.completed(isOnDevice: true))) {
            $0.aiProcessingStatus = .completed(isOnDevice: true)
        }

        // リロードで新しい要約が反映
        await store.receive(\.memoLoaded.success) {
            $0.aiSummary = MemoDetailReducer.State.AISummaryState(
                summaryText: "新しい要約（再生成）",
                keyPoints: ["新ポイント"],
                providerType: "on_device_llama_cpp",
                isOnDevice: true,
                generatedAt: newSummaryDate
            )
            $0.isAISummaryAvailable = true
        }

        XCTAssertEqual(store.state.aiSummary?.summaryText, "新しい要約（再生成）")
    }

    // MARK: - Test 4: AI処理 processing ステータスのリアルタイム更新

    func test_AIステータス_processing_リアルタイム更新() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト用テキスト")
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
            $0.aiQuota.remainingCount = { 10 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + quotaInfoLoaded）の順序が非決定的なため
        store.exhaustivity = .off

        // 初回ロード
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success)

        // ステータス更新: queued
        await store.send(.aiProcessingStatusUpdated(.queued)) {
            $0.aiProcessingStatus = .queued
        }

        // ステータス更新: processing 30%
        await store.send(.aiProcessingStatusUpdated(
            .processing(progress: 0.3, description: "LLMモデルを準備中...")
        )) {
            $0.aiProcessingStatus = .processing(progress: 0.3, description: "LLMモデルを準備中...")
        }

        // ステータス更新: processing 50%
        await store.send(.aiProcessingStatusUpdated(
            .processing(progress: 0.5, description: "メモを整理中...")
        )) {
            $0.aiProcessingStatus = .processing(progress: 0.5, description: "メモを整理中...")
        }

        // ステータス更新: processing 80%
        await store.send(.aiProcessingStatusUpdated(
            .processing(progress: 0.8, description: "結果を保存中...")
        )) {
            $0.aiProcessingStatus = .processing(progress: 0.8, description: "結果を保存中...")
        }
    }

    // MARK: - Test 5: AI処理失敗 → エラーステータス表示

    func test_AI処理失敗_エラーステータス表示() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト用テキスト")
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
            $0.aiQuota.remainingCount = { 10 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + quotaInfoLoaded）の順序が非決定的なため
        store.exhaustivity = .off

        // 初回ロード
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success)

        // AI処理失敗ステータス
        await store.send(.aiProcessingStatusUpdated(
            .failed(.processingFailed("LLM推論に失敗しました"))
        )) {
            $0.aiProcessingStatus = .failed(.processingFailed("LLM推論に失敗しました"))
        }

        // AI要約は生成されないことを確認
        XCTAssertNil(store.state.aiSummary)
    }

    // MARK: - Test 6: AI要約カード展開/折りたたみ

    func test_toggleSummaryExpanded_展開と折りたたみ() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                isSummaryExpanded: false
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.toggleSummaryExpanded) {
            $0.isSummaryExpanded = true
        }

        await store.send(.toggleSummaryExpanded) {
            $0.isSummaryExpanded = false
        }
    }

    // MARK: - Test 7: クォータ情報更新

    func test_quotaInfoLoaded_クォータ情報が正しく更新される() async {
        // onAppear の並行エフェクトの順序は不定のため、
        // _quotaInfoLoaded アクションを直接送信してクォータ更新を検証する
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                remainingQuota: 10,
                quotaLimit: 10
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(._quotaInfoLoaded(remaining: 5, limit: 10)) {
            $0.remainingQuota = 5
            $0.quotaLimit = 10
        }
    }

    // MARK: - Test 8: AI処理完了後にクォータ情報も更新される

    func test_AI処理完了後_クォータ情報も更新される() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト用テキスト")
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                remainingQuota: 10,
                quotaLimit: 10
            )
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiQuota.remainingCount = { 9 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        await store.send(.aiProcessingStatusUpdated(.completed(isOnDevice: true))) {
            $0.aiProcessingStatus = .completed(isOnDevice: true)
        }

        // completed 時: メモ詳細リロード + クォータ情報更新（順序非決定的）
        await store.skipReceivedActions()

        // クォータ情報が更新されたことを確認
        XCTAssertEqual(store.state.remainingQuota, 9)
        XCTAssertEqual(store.state.quotaLimit, 10)
    }

    // MARK: - Test 9: triggerAIProcessing エラー時のフォールバック

    func test_triggerAIProcessing_エンキューエラー_failedステータス() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.aiProcessingQueue.enqueueProcessing = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "キュー追加に失敗"])
            }
        }
        await store.send(.triggerAIProcessing) {
            $0.aiProcessingStatus = .queued
        }

        await store.receive(.aiProcessingStatusUpdated(
            .failed(.processingFailed("キュー追加に失敗"))
        )) {
            $0.aiProcessingStatus = .failed(.processingFailed("キュー追加に失敗"))
        }
    }

    // MARK: - Helper

    private func makeEntity(
        id: UUID? = nil,
        title: String = "テストメモ",
        createdAt: Date? = nil,
        durationSeconds: Double = 180,
        transcription: TranscriptionEntity? = nil,
        aiSummary: AISummaryEntity? = nil,
        emotion: EmotionAnalysisEntity? = nil,
        tags: [TagEntity] = []
    ) -> VoiceMemoEntity {
        VoiceMemoEntity(
            id: id ?? testMemoID,
            title: title,
            createdAt: createdAt ?? testDate,
            durationSeconds: durationSeconds,
            audioFilePath: "Audio/test.m4a",
            transcription: transcription,
            aiSummary: aiSummary,
            emotionAnalysis: emotion,
            tags: tags
        )
    }
}
