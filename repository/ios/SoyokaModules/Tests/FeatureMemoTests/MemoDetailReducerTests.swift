import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureMemo

@MainActor
final class MemoDetailReducerTests: XCTestCase {

    // MARK: - Test Helpers

    private let testMemoID = UUID()
    private let testDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let testTagID = UUID()

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

    /// 共通のDependency設定（aiQuota含む）
    private func configureDependencies(
        _ deps: inout DependencyValues,
        entity: VoiceMemoEntity
    ) {
        deps.voiceMemoRepository.fetchMemoDetail = { _ in entity }
        deps.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        deps.aiQuota.remainingCount = { 10 }
        deps.aiQuota.monthlyLimit = { 10 }
        deps.subscriptionClient.currentSubscription = { .free }
        deps.relatedMemo.findRelated = { _, _, _ in [] }
    }

    // MARK: - Test 1: メモ詳細データのロード

    func test_onAppear_メモ詳細データのロード() async {
        let entity = makeEntity(
            title: "テストメモ",
            transcription: TranscriptionEntity(
                fullText: "テスト文字起こしテキスト全文",
                language: "ja-JP",
                confidence: 0.95
            ),
            emotion: EmotionAnalysisEntity(
                primaryEmotion: .joy,
                confidence: 0.85
            ),
            tags: [TagEntity(id: testTagID, name: "テスト", source: .ai)]
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity)
        }
        // exhaustivity = .off: onAppear が memoLoaded + observeStatus + _quotaInfoLoaded の3つの
        // 並行エフェクトを .merge で起動し、受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.createdAt = self.testDate
            $0.updatedAt = self.testDate
            $0.durationSeconds = 180
            $0.audioFilePath = "Audio/test.m4a"
            $0.transcriptionText = "テスト文字起こしテキスト全文"
            $0.transcriptionLanguage = "ja-JP"
            $0.transcriptionConfidence = 0.95
            $0.aiSummary = nil
            $0.isAISummaryAvailable = false
            $0.emotion = MemoDetailReducer.State.EmotionState(
                category: .joy,
                confidence: 0.85,
                emotionDescription: "感情分析結果"
            )
            $0.tags = [
                MemoDetailReducer.State.TagItem(
                    id: self.testTagID,
                    name: "テスト",
                    source: "ai"
                )
            ]
            $0.audioPlayer = AudioPlayerReducer.State(
                audioFilePath: "Audio/test.m4a"
            )
        }

    }

    // MARK: - Test 2: 文字起こしテキストが設定される

    func test_memoLoaded_文字起こしテキストが設定される() async {
        let fullText = "これは長い文字起こしテキストです。複数の文が含まれています。テスト用のテキストです。"
        let entity = makeEntity(
            transcription: TranscriptionEntity(
                fullText: fullText,
                language: "ja-JP",
                confidence: 0.92
            )
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity)
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + _quotaInfoLoaded）の受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.createdAt = self.testDate
            $0.updatedAt = self.testDate
            $0.durationSeconds = 180
            $0.audioFilePath = "Audio/test.m4a"
            $0.transcriptionText = fullText
            $0.transcriptionLanguage = "ja-JP"
            $0.transcriptionConfidence = 0.92
            $0.isAISummaryAvailable = false
            $0.audioPlayer = AudioPlayerReducer.State(
                audioFilePath: "Audio/test.m4a"
            )
        }

        XCTAssertEqual(store.state.transcriptionText, fullText)
    }

    // MARK: - Test 3: AI要約がある場合

    func test_memoLoaded_AI要約がある場合() async {
        let summaryDate = Date(timeIntervalSince1970: 1_700_000_100)
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト"),
            aiSummary: AISummaryEntity(
                summaryText: "AI要約テキスト",
                keyPoints: ["ポイント1", "ポイント2"],
                providerType: .onDeviceLlamaCpp,
                isOnDevice: true,
                generatedAt: summaryDate
            )
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity)
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + _quotaInfoLoaded）の受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.createdAt = self.testDate
            $0.updatedAt = self.testDate
            $0.durationSeconds = 180
            $0.audioFilePath = "Audio/test.m4a"
            $0.transcriptionText = "テスト"
            $0.transcriptionLanguage = "ja-JP"
            $0.transcriptionConfidence = 0.0
            $0.aiSummary = MemoDetailReducer.State.AISummaryState(
                summaryText: "AI要約テキスト",
                keyPoints: ["ポイント1", "ポイント2"],
                providerType: "on_device_llama_cpp",
                isOnDevice: true,
                generatedAt: summaryDate
            )
            $0.isAISummaryAvailable = true
            $0.audioPlayer = AudioPlayerReducer.State(
                audioFilePath: "Audio/test.m4a"
            )
        }

    }

    // MARK: - Test 4: AI要約がない場合

    func test_memoLoaded_AI要約がない場合() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト")
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity)
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + _quotaInfoLoaded）の受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.createdAt = self.testDate
            $0.updatedAt = self.testDate
            $0.durationSeconds = 180
            $0.audioFilePath = "Audio/test.m4a"
            $0.transcriptionText = "テスト"
            $0.transcriptionLanguage = "ja-JP"
            $0.transcriptionConfidence = 0.0
            $0.aiSummary = nil
            $0.isAISummaryAvailable = false
            $0.audioPlayer = AudioPlayerReducer.State(
                audioFilePath: "Audio/test.m4a"
            )
        }

        XCTAssertNil(store.state.aiSummary)
        XCTAssertFalse(store.state.isAISummaryAvailable)
    }

    // MARK: - Test 5: 感情分析がある場合

    func test_memoLoaded_感情分析がある場合() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト"),
            emotion: EmotionAnalysisEntity(
                primaryEmotion: .calm,
                confidence: 0.90
            )
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity)
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + _quotaInfoLoaded）の受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.createdAt = self.testDate
            $0.updatedAt = self.testDate
            $0.durationSeconds = 180
            $0.audioFilePath = "Audio/test.m4a"
            $0.transcriptionText = "テスト"
            $0.transcriptionLanguage = "ja-JP"
            $0.transcriptionConfidence = 0.0
            $0.isAISummaryAvailable = false
            $0.emotion = MemoDetailReducer.State.EmotionState(
                category: .calm,
                confidence: 0.90,
                emotionDescription: "感情分析結果"
            )
            $0.audioPlayer = AudioPlayerReducer.State(
                audioFilePath: "Audio/test.m4a"
            )
        }

        XCTAssertEqual(store.state.emotion?.category, .calm)
    }

    // MARK: - Test 6: タグ一覧が設定される

    func test_memoLoaded_タグ一覧が設定される() async {
        let tag1ID = UUID()
        let tag2ID = UUID()
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト"),
            tags: [
                TagEntity(id: tag1ID, name: "アイデア", source: .ai),
                TagEntity(id: tag2ID, name: "仕事", source: .manual),
            ]
        )

        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            self.configureDependencies(&$0, entity: entity)
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + _quotaInfoLoaded）の受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.success) {
            $0.isLoading = false
            $0.title = "テストメモ"
            $0.createdAt = self.testDate
            $0.updatedAt = self.testDate
            $0.durationSeconds = 180
            $0.audioFilePath = "Audio/test.m4a"
            $0.transcriptionText = "テスト"
            $0.transcriptionLanguage = "ja-JP"
            $0.transcriptionConfidence = 0.0
            $0.isAISummaryAvailable = false
            $0.tags = [
                MemoDetailReducer.State.TagItem(id: tag1ID, name: "アイデア", source: "ai"),
                MemoDetailReducer.State.TagItem(id: tag2ID, name: "仕事", source: "manual"),
            ]
            $0.audioPlayer = AudioPlayerReducer.State(
                audioFilePath: "Audio/test.m4a"
            )
        }

        XCTAssertEqual(store.state.tags.count, 2)
    }

    // MARK: - Test 7: エラーメッセージ表示

    func test_memoLoaded_failure_エラーメッセージ表示() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.fetchMemoDetail = { _ in
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "メモが見つかりません"])
            }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
            $0.aiQuota.remainingCount = { 10 }
            $0.aiQuota.monthlyLimit = { 10 }
        }
        // exhaustivity = .off: onAppear の並行エフェクト（memoLoaded + observeStatus + _quotaInfoLoaded）の受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.memoLoaded.failure) {
            $0.isLoading = false
            $0.errorMessage = "メモが見つかりません"
        }

    }

    // MARK: - Test 8: editButtonTapped → 編集シート表示

    func test_editButtonTapped_編集シート表示() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                title: "テストメモ",
                transcriptionText: "テスト文字起こし"
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.editButtonTapped) {
            $0.editState = MemoEditReducer.State(
                memoID: self.testMemoID,
                title: "テストメモ",
                transcriptionText: "テスト文字起こし",
                originalTitle: "テストメモ",
                originalTranscriptionText: "テスト文字起こし"
            )
        }
    }

    // MARK: - Test 9: tagTapped タグ名が伝播

    func test_tagTapped_タグ名が伝播() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        }

        await store.send(.tagTapped("アイデア"))
    }

    // MARK: - Test 10: deleteButtonTapped → 確認ダイアログ表示

    func test_deleteButtonTapped_確認ダイアログ表示() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        }

        await store.send(.deleteButtonTapped) {
            $0.showDeleteConfirmation = true
        }
    }

    // MARK: - Test 11: 削除確認 → 削除実行 → 完了アクション

    func test_deleteConfirmed_削除実行() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.voiceMemoRepository.getAudioFilePath = { _ in "Audio/test.m4a" }
            $0.voiceMemoRepository.delete = { _ in }
            $0.audioFileStore.deleteAudioFile = { _ in }
            $0.fts5IndexManager.removeIndex = { _ in }
        }
        await store.send(.delete(.deleteConfirmed(id: testMemoID))) {
            $0.deleteState.showDeleteConfirmation = false
            $0.deleteState.isDeleting = true
        }

        await store.receive(\.delete.deleteCompleted) {
            $0.deleteState.isDeleting = false
            $0.deleteState.pendingDeleteID = nil
        }

        // 削除完了後に AppReducer への伝播アクション
        await store.receive(\._deleteCompletedAndDismiss)
    }

    // MARK: - Test 12: 編集シートを閉じる

    func test_dismissEditSheet_編集シートを閉じる() async {
        let store = TestStore(
            initialState: MemoDetailReducer.State(
                memoID: testMemoID,
                editState: MemoEditReducer.State(
                    memoID: testMemoID,
                    title: "テスト",
                    transcriptionText: "テスト文字起こし"
                )
            )
        ) {
            MemoDetailReducer()
        }

        await store.send(.dismissEditSheet) {
            $0.editState = nil
        }
    }

    // MARK: - Test 13: T09 regenerateAISummary → AI処理キューに追加

    func test_regenerateAISummary_AI処理キューに追加() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        var enqueuedMemoID: UUID?
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.aiProcessingQueue.enqueueProcessing = { id in
                enqueuedMemoID = id
            }
        }

        await store.send(.regenerateAISummary) {
            $0.aiProcessingStatus = .queued
        }

        XCTAssertEqual(enqueuedMemoID, testMemoID)
    }

    // MARK: - Test 14: T10 toggleSummaryExpanded

    func test_toggleSummaryExpanded_展開折りたたみ切替() async {
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

    // MARK: - Test 15: T09 triggerAIProcessing → AI処理キューに追加

    func test_triggerAIProcessing_AI処理をトリガー() async {
        UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasSeenAIOnboarding") }

        var enqueuedMemoID: UUID?
        let store = TestStore(
            initialState: MemoDetailReducer.State(memoID: testMemoID)
        ) {
            MemoDetailReducer()
        } withDependencies: {
            $0.aiProcessingQueue.enqueueProcessing = { id in
                enqueuedMemoID = id
            }
        }

        await store.send(.triggerAIProcessing) {
            $0.aiProcessingStatus = .queued
        }

        XCTAssertEqual(enqueuedMemoID, testMemoID)
    }

    // MARK: - Test 16: T09 AI処理完了時にクォータ情報も更新される

    func test_aiProcessingStatusUpdated_completed_クォータ更新() async {
        let entity = makeEntity(
            transcription: TranscriptionEntity(fullText: "テスト")
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
            $0.aiQuota.remainingCount = { 14 }
            $0.aiQuota.monthlyLimit = { 10 }
        }

        // exhaustivity = .off: completed 時に memoLoaded + _quotaInfoLoaded の並行エフェクトが発生し、受信順序が非決定的なため
        store.exhaustivity = .off

        await store.send(.aiProcessingStatusUpdated(.completed(isOnDevice: true))) {
            $0.aiProcessingStatus = .completed(isOnDevice: true)
        }
    }
}
