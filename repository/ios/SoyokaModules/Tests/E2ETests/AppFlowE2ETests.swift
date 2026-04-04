import AVFoundation
import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureAI
@testable import FeatureMemo
@testable import FeatureRecording

// MARK: - E2E統合テスト
// 主要フロー3本のEnd-to-End統合テスト
// 複数Reducerを組み合わせ、モック注入でフルフローを検証する

@MainActor
final class AppFlowE2ETests: XCTestCase {

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

    // MARK: - Test 1: 録音→保存→一覧表示フロー

    /// 録音開始→文字起こし受信→停止→保存完了→一覧に反映されるE2Eフロー
    func test_録音から保存して一覧に表示されるフロー() async {
        let recordingID = UUID()
        let now = Date()

        // ---- Phase 1: 録音 → 保存 ----

        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 10.0,
            format: .m4a
        )
        let savedMemo = VoiceMemoEntity(
            id: recordingID,
            title: "テスト録音",
            createdAt: now,
            durationSeconds: 10.0,
            audioFilePath: "Audio/\(recordingID.uuidString).m4a",
            transcription: TranscriptionEntity(
                fullText: "今日はいい天気でした",
                language: "ja-JP",
                confidence: 0.9
            )
        )

        let recordingStore = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 10.0,
                partialTranscription: "今日はいい天気でした",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { _ in }
            $0.temporaryRecordingStore.cleanup = { _ in }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: stopButtonTapped → recordingSaved → completionStageAdvanced の
        // 一連エフェクトが発生し、完了まで追跡が困難なため
        recordingStore.exhaustivity = .off

        // 停止 → 保存
        await recordingStore.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        await recordingStore.receive(\.recordingSaved)

        // saved 状態になったことを確認
        guard case let .saved(memo) = recordingStore.state.recordingStatus else {
            XCTFail("recordingStatusが.savedではありません: \(recordingStore.state.recordingStatus)")
            return
        }
        XCTAssertEqual(memo.transcription?.fullText, "今日はいい天気でした")

        // ---- Phase 2: 一覧に保存したメモが表示される ----

        let listStore = TestStore(
            initialState: MemoListReducer.State()
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemos = { _, _ in [savedMemo] }
            $0.date.now = now
            $0.calendar = Calendar.current
            $0.aiQuota.currentUsage = { 0 }
            $0.aiQuota.monthlyLimit = { 10 }
            $0.aiQuota.nextResetDate = { Date() }
            $0.aiQuota.remainingCount = { 10 }
        }
        // exhaustivity = .off: onAppear が memosLoaded + aiQuotaLoaded の並行エフェクトを .merge で起動し、
        // 受信順序が非決定的なため
        listStore.exhaustivity = .off

        await listStore.send(.onAppear) {
            $0.isLoading = true
        }

        await listStore.receive(\.memosLoaded.success) {
            $0.isLoading = false
            $0.currentPage = 1
            $0.hasMorePages = false
            $0.memos = IdentifiedArrayOf(uniqueElements: [
                MemoListReducer.MemoItem(
                    id: recordingID,
                    title: "テスト録音",
                    createdAt: now,
                    durationSeconds: 10.0,
                    transcriptPreview: String("今日はいい天気でした".prefix(60)),
                    emotion: nil,
                    tags: [],
                    audioFilePath: "Audio/\(recordingID.uuidString).m4a"
                ),
            ])
            $0.sections = MemoListReducer.buildSections(
                from: $0.memos,
                now: now,
                calendar: Calendar.current
            )
        }

        // 一覧のメモ数を確認
        XCTAssertEqual(listStore.state.memos.count, 1)
        XCTAssertEqual(listStore.state.memos.first?.title, "テスト録音")
    }

    // MARK: - Test 2: 検索フロー

    /// MemoListReducerで検索クエリ入力→FTS5検索→結果表示のフロー
    func test_検索クエリ入力から結果表示までのフロー() async {
        let memoID = UUID()
        let now = Date()

        let existingMemo = makeMemoItem(
            id: memoID,
            title: "散歩メモ",
            createdAt: now,
            durationSeconds: 60,
            transcriptPreview: "今日は公園を散歩しました",
            tags: ["散歩"]
        )

        let store = TestStore(
            initialState: MemoListReducer.State(
                memos: IdentifiedArrayOf(uniqueElements: [existingMemo]),
                sections: MemoListReducer.buildSections(
                    from: IdentifiedArrayOf(uniqueElements: [existingMemo]),
                    now: now,
                    calendar: Calendar.current
                )
            )
        ) {
            MemoListReducer()
        } withDependencies: {
            $0.fts5IndexManager.searchWithSnippets = { query, _, _ in
                XCTAssertEqual(query, "散歩")
                return [
                    FTS5SearchResult(
                        memoID: memoID.uuidString,
                        snippet: "今日は公園を<b>散歩</b>しました",
                        rank: 1.0
                    ),
                ]
            }
            $0.voiceMemoRepository.fetchMemosByIDs = { ids in
                XCTAssertEqual(ids, [memoID])
                return [
                    memoID: SearchableMemo(
                        title: "散歩メモ",
                        createdAt: now,
                        emotion: nil,
                        durationSeconds: 60,
                        tags: ["散歩"]
                    ),
                ]
            }
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
            $0.calendar = Calendar.current
        }
        // exhaustivity = .off: searchQueryChanged → debounce → searchCompleted のエフェクトチェーンと
        // キャンセル可能なストリームの完了追跡が困難なため
        store.exhaustivity = .off

        // 検索クエリを入力
        await store.send(.searchQueryChanged("散歩")) {
            $0.search.query = "散歩"
            $0.search.isSearching = true
        }

        // 検索結果を受信
        await store.receive(\.searchCompleted) {
            $0.search.isSearching = false
            $0.search.results = [
                MemoListReducer.SearchResultItem(
                    id: memoID,
                    title: "散歩メモ",
                    snippet: "今日は公園を<b>散歩</b>しました",
                    createdAt: now,
                    emotion: nil,
                    durationSeconds: 60,
                    tags: ["散歩"]
                ),
            ]
        }

        // 検索結果の件数と内容を検証
        XCTAssertEqual(store.state.search.results.count, 1)
        XCTAssertEqual(store.state.search.results.first?.title, "散歩メモ")
        XCTAssertTrue(store.state.search.isActive)

        // 検索をクリア
        await store.send(.searchQueryChanged("")) {
            $0.search.query = ""
            $0.search.results = []
            $0.search.isSearching = false
        }

        XCTAssertFalse(store.state.search.isActive)
    }

    // MARK: - Test 3: AI処理キュー→結果反映フロー

    /// AIProcessingReducerでstartProcessing→クォータチェック→キュー投入→processing→completed のフルフロー
    func test_AI処理キューから完了までのフルフロー() async {
        let memoID = UUID()
        let testResetDate = Date(timeIntervalSince1970: 1_800_000_000)

        // オンボーディング済みに設定
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        let statusStream = AsyncStream<AIProcessingStatus>.makeStream()
        let enqueuedMemoID = LockIsolated<UUID?>(nil)

        let store = TestStore(
            initialState: AIProcessingReducer.State(
                memoID: memoID,
                remainingQuota: 10,
                quotaUsed: 0,
                quotaLimit: 10
            )
        ) {
            AIProcessingReducer()
        } withDependencies: {
            $0.aiQuota.canProcess = { true }
            $0.aiQuota.remainingCount = { 14 }
            $0.aiQuota.currentUsage = { 1 }
            $0.aiQuota.monthlyLimit = { 10 }
            $0.aiQuota.nextResetDate = { testResetDate }
            $0.aiProcessingQueue.enqueueProcessing = { id in
                enqueuedMemoID.withValue { $0 = id }
            }
            $0.aiProcessingQueue.observeStatus = { _ in statusStream.stream }
        }
        // exhaustivity = .off: _quotaCheckCompleted 後に observeStatus の cancellable ストリームが
        // 長時間running effectとして残り続けるため、exhaustive モードでは完了を待てない
        store.exhaustivity = .off

        // ---- Phase 1: 処理開始 → クォータチェック ----
        await store.send(.startProcessing)

        await store.receive(._quotaCheckCompleted(canProcess: true, remaining: 14, used: 1)) {
            $0.remainingQuota = 14
            $0.quotaUsed = 1
            $0.quotaLimit = 10
        }

        // enqueueProcessing が呼ばれたことを確認
        XCTAssertEqual(enqueuedMemoID.value, memoID)

        // ---- Phase 2: キューに入った → processing ----
        statusStream.continuation.yield(.queued)
        await store.receive(.statusUpdated(.queued)) {
            $0.processingStatus = .queued
        }

        statusStream.continuation.yield(.processing(progress: 0.3, description: "文字起こしを分析中..."))
        await store.receive(.statusUpdated(.processing(progress: 0.3, description: "文字起こしを分析中..."))) {
            $0.processingStatus = .processing(progress: 0.3, description: "文字起こしを分析中...")
        }

        statusStream.continuation.yield(.processing(progress: 0.7, description: "要約を生成中..."))
        await store.receive(.statusUpdated(.processing(progress: 0.7, description: "要約を生成中..."))) {
            $0.processingStatus = .processing(progress: 0.7, description: "要約を生成中...")
        }

        // ---- Phase 3: 処理完了 → クォータ更新 ----
        statusStream.continuation.yield(.completed(isOnDevice: true))
        await store.receive(.statusUpdated(.completed(isOnDevice: true))) {
            $0.processingStatus = .completed(isOnDevice: true)
        }

        // completed 時のクォータ更新エフェクト
        await store.receive(.quotaUpdated(used: 1, remaining: 14))

        // 最終状態の検証
        XCTAssertEqual(store.state.processingStatus, .completed(isOnDevice: true))
        XCTAssertEqual(store.state.remainingQuota, 14)
        XCTAssertEqual(store.state.quotaUsed, 1)

        statusStream.continuation.finish()
    }
}
