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
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        }

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
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        }

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
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        }

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
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        }

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
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        }

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
            $0.voiceMemoRepository.fetchMemoDetail = { _ in entity }
            $0.aiProcessingQueue.observeStatus = { _ in AsyncStream { $0.finish() } }
        }

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
        }

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
        // 現時点ではアクションは.noneを返す（将来のタグフィルター機能で利用）
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
        // TODO: exhaustivity = .off を解消し、削除完了後の全アクション（_deleteCompletedAndDismiss等）を明示的に検証する
        store.exhaustivity = .off

        await store.send(.delete(.deleteConfirmed(id: testMemoID))) {
            $0.deleteState.showDeleteConfirmation = false
            $0.deleteState.isDeleting = true
        }
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
}
