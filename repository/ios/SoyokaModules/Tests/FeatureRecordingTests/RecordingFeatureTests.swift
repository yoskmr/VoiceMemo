import AVFoundation
import ComposableArchitecture
import Dependencies
import XCTest
@testable import Domain
@testable import FeatureRecording

@MainActor
final class RecordingFeatureTests: XCTestCase {

    // MARK: - 正常系: recordButtonTapped → recording状態

    /// 権限許可済みで録音ボタンタップ → recordingに遷移する
    func test_recordButtonTapped_権限許可済み_recordingに遷移する() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.startRecording = { (levels: AsyncStream<AudioLevelUpdate> { $0.finish() }, pcmBuffers: AsyncStream<AVAudioPCMBuffer> { $0.finish() }) }
            $0.sttEngine.startTranscription = { _, _ in AsyncStream<TranscriptionResult> { $0.finish() } }
            $0.sttEngine.setCustomDictionary = { _ in }
            $0.customDictionaryClient.getContextualStrings = { [] }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: recordButtonTapped が startRecordingEffect（STTストリーム+音声レベル監視）と
        // startTimerEffect（1秒間隔タイマー）を .merge で起動し、両方とも長時間running effectのため解消困難
        store.exhaustivity = .off

        await store.send(.recordButtonTapped) {
            $0.recordingStatus = .recording
            $0.elapsedTime = 0
            $0.partialTranscription = ""
            $0.confirmedTranscription = ""
            $0.errorMessage = nil
        }
    }

    /// 権限未許可で録音ボタンタップ → permissionRequestedが送信される
    func test_recordButtonTapped_権限未許可_permissionRequestedが送信される() async {
        let permissionGranted = false
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: false)
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.requestPermission = { permissionGranted }
        }

        await store.send(.recordButtonTapped)

        await store.receive(.permissionRequested)

        await store.receive(.permissionResponse(permissionGranted))
    }

    // MARK: - 正常系: pauseButtonTapped → paused状態

    /// 録音中に一時停止ボタンタップ → pausedに遷移しタイマーがキャンセルされる
    func test_pauseButtonTapped_recording中_pausedに遷移しタイマーがキャンセルされる() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .recording,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.pauseRecording = {}
        }

        await store.send(.pauseButtonTapped) {
            $0.recordingStatus = .paused
        }
    }

    /// 一時停止中にpauseRecordingが失敗 → recordingFailedが送信される
    func test_pauseButtonTapped_失敗時_recordingFailedが送信される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .recording,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.pauseRecording = {
                throw NSError(domain: "Audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "一時停止に失敗"])
            }
        }

        await store.send(.pauseButtonTapped) {
            $0.recordingStatus = .paused
        }

        await store.receive(\.recordingFailed) {
            $0.recordingStatus = .idle
            $0.errorMessage = "一時停止に失敗"
        }
    }

    // MARK: - 正常系: resumeButtonTapped → recording状態

    /// 一時停止中に再開ボタンタップ → recordingに遷移しタイマーが再開される
    func test_resumeButtonTapped_paused中_recordingに遷移しタイマーが再開される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .paused,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.resumeRecording = {}
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: resumeButtonTapped が startTimerEffect（1秒間隔タイマー）と
        // resumeRecording の .merge を起動し、タイマーが長時間running effectのため解消困難
        store.exhaustivity = .off

        await store.send(.resumeButtonTapped) {
            $0.recordingStatus = .recording
        }
    }

    /// 再開時にresumeRecordingが失敗 → recordingFailedが送信される
    func test_resumeButtonTapped_失敗時_recordingFailedが送信される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .paused,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.resumeRecording = {
                throw NSError(domain: "Audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "再開に失敗"])
            }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: resumeButtonTapped が startTimerEffect（1秒間隔タイマー）と
        // resumeRecording の .merge を起動し、タイマーが長時間running effectのため解消困難
        store.exhaustivity = .off

        await store.send(.resumeButtonTapped) {
            $0.recordingStatus = .recording
        }

        await store.receive(\.recordingFailed) {
            $0.recordingStatus = .idle
            $0.errorMessage = "再開に失敗"
        }
    }

    // MARK: - 正常系: stopButtonTapped → saving → 保存完了

    /// 録音中に停止ボタンタップ → savingに遷移し、sttFinalized経由で完了画面（saved状態）に遷移する
    func test_stopButtonTapped_recording中_savingに遷移し保存完了する() async {
        let recordingID = UUID()
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 10.0,
            format: .m4a
        )

        let savedMemos = LockIsolated<[VoiceMemoEntity]>([])

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 10.0,
                partialTranscription: "テスト文字起こし",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "テスト文字起こし（最終）", confidence: 0.9, isFinal: true, language: "ja-JP")
            }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { memo in savedMemos.withValue { $0.append(memo) } }
            $0.temporaryRecordingStore.cleanup = { _ in }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: stopButtonTapped → sttFinalized → recordingSaved → completionStageAdvanced の
        // 一連のエフェクトが発生し、recordingSaved で動的に生成される VoiceMemoEntity の完全一致検証が困難なため
        store.exhaustivity = .off

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → saveRecordingEffect → recordingSaved
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingSaved)

        // saved状態であることを確認
        guard case let .saved(savedMemo) = store.state.recordingStatus else {
            XCTFail("recordingStatusが.savedではありません: \(store.state.recordingStatus)")
            return
        }
        XCTAssertEqual(savedMemo.id, recordingID)
        XCTAssertEqual(savedMemo.durationSeconds, 10.0)
        // state.partialTranscription（最新テキスト）が使われるため、フォールバックではなくstate値が保存される
        XCTAssertEqual(savedMemo.transcription?.fullText, "テスト文字起こし")

        // VoiceMemoが正しく保存されたことを確認
        savedMemos.withValue { memos in
            XCTAssertEqual(memos.count, 1)
            XCTAssertEqual(memos.first?.id, recordingID)
            XCTAssertEqual(memos.first?.durationSeconds, 10.0)
            XCTAssertEqual(memos.first?.transcription?.fullText, "テスト文字起こし")
        }
    }

    /// 録音停止時にSTT確定が失敗しテキストが空でも、1秒超なら音声を保持して保存する
    func test_stopButtonTapped_STT失敗でテキスト空_1秒超なら音声を保持して保存する() async {
        let recordingID = UUID()
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 5.0,
            format: .m4a
        )

        let savedMemos = LockIsolated<[VoiceMemoEntity]>([])

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 5.0,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "", confidence: 0.0, isFinal: true, language: "ja-JP")
            }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { memo in savedMemos.withValue { $0.append(memo) } }
            $0.temporaryRecordingStore.cleanup = { _ in }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: sttFinalized → recordingSaved → completionStageAdvanced の
        // 一連のエフェクト追跡が困難
        store.exhaustivity = .off

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → テキスト空でも1秒超のため保存される → recordingSavedが送信される
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingSaved)

        // VoiceMemoが保存されたことを確認
        savedMemos.withValue { memos in
            XCTAssertEqual(memos.count, 1)
            XCTAssertEqual(memos.first?.id, recordingID)
        }
    }

    // MARK: - 正常系: stopButtonTapped → 空テキスト + 1秒超で音声保持して保存

    /// 文字起こしテキストが空でも1秒超なら音声を保持して保存する
    func test_stopButtonTapped_空テキスト_1秒超なら音声を保持して保存する() async {
        let recordingID = UUID()
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 3.0,
            format: .m4a
        )

        let savedMemos = LockIsolated<[VoiceMemoEntity]>([])

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 3.0,
                partialTranscription: "",
                confirmedTranscription: "",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "", confidence: 0.0, isFinal: true, language: "ja-JP")
            }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { memo in savedMemos.withValue { $0.append(memo) } }
            $0.temporaryRecordingStore.cleanup = { _ in }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: sttFinalized → recordingSaved → completionStageAdvanced の
        // 一連のエフェクト追跡が困難
        store.exhaustivity = .off

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → テキスト空でも1秒超のため保存される
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingSaved)

        savedMemos.withValue { memos in
            XCTAssertEqual(memos.count, 1)
            XCTAssertEqual(memos.first?.id, recordingID)
        }
    }

    /// 文字起こしテキストが空白のみでも1秒超なら音声を保持して保存する
    func test_stopButtonTapped_空白のみテキスト_1秒超なら音声を保持して保存する() async {
        let recordingID = UUID()
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 2.0,
            format: .m4a
        )

        let savedMemos = LockIsolated<[VoiceMemoEntity]>([])

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 2.0,
                partialTranscription: "   \n  ",
                confirmedTranscription: "",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "   \n  ", confidence: 0.0, isFinal: true, language: "ja-JP")
            }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { memo in savedMemos.withValue { $0.append(memo) } }
            $0.temporaryRecordingStore.cleanup = { _ in }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: sttFinalized → recordingSaved → completionStageAdvanced の
        // 一連のエフェクト追跡が困難
        store.exhaustivity = .off

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → 空白のみでも1秒超のため保存される
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingSaved)

        savedMemos.withValue { memos in
            XCTAssertEqual(memos.count, 1)
            XCTAssertEqual(memos.first?.id, recordingID)
        }
    }

    // MARK: - 正常系: stopButtonTapped → 空テキスト + 1秒以下で誤タップとみなし削除

    /// 1秒以下の空テキスト録音は誤タップとみなし、音声ファイルを削除する
    func test_stopButtonTapped_空テキスト_1秒以下なら誤タップとみなし削除する() async {
        let recordingID = UUID()
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 0.5,
            format: .m4a
        )

        let cleanupCalled = LockIsolated(false)

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 0.5,
                partialTranscription: "",
                confirmedTranscription: "",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "", confidence: 0.0, isFinal: true, language: "ja-JP")
            }
            $0.temporaryRecordingStore.cleanup = { _ in cleanupCalled.setValue(true) }
        }

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → saveRecordingEffect → 1秒以下の空テキストなので誤タップ → recordingFailed
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingFailed) {
            $0.recordingStatus = .idle
            $0.errorMessage = "何も話されませんでした"
        }

        // 一時ファイルのクリーンアップが呼ばれたことを確認
        XCTAssertTrue(cleanupCalled.value)
    }

    /// ちょうど1秒の空テキスト録音は誤タップとみなし、音声ファイルを削除する
    func test_stopButtonTapped_空テキスト_ちょうど1秒なら誤タップとみなし削除する() async {
        let recordingID = UUID()
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 1.0,
            format: .m4a
        )

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingID: recordingID,
                recordingStatus: .recording,
                elapsedTime: 1.0,
                partialTranscription: "",
                confirmedTranscription: "",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "", confidence: 0.0, isFinal: true, language: "ja-JP")
            }
            $0.temporaryRecordingStore.cleanup = { _ in }
        }

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → ちょうど1秒（<= 1.0）なので誤タップ → recordingFailedが送信される
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingFailed) {
            $0.recordingStatus = .idle
            $0.errorMessage = "何も話されませんでした"
        }
    }

    // MARK: - 異常系: 録音停止後の保存失敗

    /// 保存失敗時にrecordingFailedが受信されエラーメッセージが設定される
    func test_stopButtonTapped_保存失敗時_recordingFailedが受信される() async {
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 10.0,
            format: .m4a
        )
        let transcriptionResult = TranscriptionResult(
            text: "テスト",
            confidence: 0.9,
            isFinal: true,
            language: "ja-JP"
        )

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .recording,
                elapsedTime: 10.0,
                partialTranscription: "テスト",
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = { transcriptionResult }
            $0.audioFileStore.moveToDocuments = { _, _ in
                throw SaveRecordingError.fileMoveFailed("ストレージ不足")
            }
        }

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        // sttFinalized → saveRecordingEffect → 保存失敗 → recordingFailed
        await store.receive(\.sttFinalized)
        await store.receive(\.recordingFailed) {
            $0.recordingStatus = .idle
            $0.errorMessage = SaveRecordingError.fileMoveFailed("ストレージ不足").localizedDescription
        }
    }

    // MARK: - 正常系: timerTicked → elapsedTimeインクリメント

    /// timerTickedで経過時間が1秒増加する
    func test_timerTicked_elapsedTimeがインクリメントされる() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .recording,
                elapsedTime: 5,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        }

        await store.send(.timerTicked) {
            $0.elapsedTime = 6
        }
    }

    // MARK: - 正常系: audioLevelUpdated → audioLevel更新

    /// audioLevelUpdatedで音声レベルが更新される
    func test_audioLevelUpdated_audioLevelが更新される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        }

        await store.send(.audioLevelUpdated(0.75)) {
            $0.audioLevel = 0.75
        }
    }

    // MARK: - 正常系: transcriptionUpdated → テキストと信頼度更新

    /// 高信頼度の文字起こし更新
    func test_transcriptionUpdated_テキストと信頼度が更新される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        }

        await store.send(.transcriptionUpdated("テスト文字起こし", 0.95, false)) {
            $0.partialTranscription = "テスト文字起こし"
            $0.confidenceLevel = .high
        }
    }

    /// 中信頼度の文字起こし更新
    func test_transcriptionUpdated_中信頼度_confidenceLevelがmediumになる() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        }

        await store.send(.transcriptionUpdated("やや不明瞭", 0.5, false)) {
            $0.partialTranscription = "やや不明瞭"
            $0.confidenceLevel = .medium
        }
    }

    /// 低信頼度の文字起こし更新
    func test_transcriptionUpdated_低信頼度_confidenceLevelがlowになる() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        }

        await store.send(.transcriptionUpdated("あいまい", 0.3, false)) {
            $0.partialTranscription = "あいまい"
            $0.confidenceLevel = .low
        }
    }

    // MARK: - 正常系: permissionResponse

    /// 権限許可レスポンスでisPermissionGrantedがtrueになる
    func test_permissionResponse_true_isPermissionGrantedがtrueになる() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: false)
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.startRecording = { (levels: AsyncStream<AudioLevelUpdate> { $0.finish() }, pcmBuffers: AsyncStream<AVAudioPCMBuffer> { $0.finish() }) }
            $0.sttEngine.startTranscription = { _, _ in AsyncStream<TranscriptionResult> { $0.finish() } }
            $0.sttEngine.setCustomDictionary = { _ in }
            $0.customDictionaryClient.getContextualStrings = { [] }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: permissionResponse(true) → recordButtonTapped → startRecordingEffect（STTストリーム+
        // 音声レベル監視）と startTimerEffect（1秒間隔タイマー）を .merge で起動し、長時間running effectのため解消困難
        store.exhaustivity = .off

        await store.send(.permissionResponse(true)) {
            $0.isPermissionGranted = true
        }
    }

    /// 権限拒否レスポンスでisPermissionGrantedがfalseのまま
    func test_permissionResponse_false_isPermissionGrantedがfalseのまま() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: false)
        ) {
            RecordingFeature()
        }

        await store.send(.permissionResponse(false))
    }

    // MARK: - 異常系: recordingFailed → エラー状態

    /// 録音失敗時にidleに遷移しエラーメッセージが設定される
    func test_recordingFailed_エラーメッセージが設定される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .recording,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        }

        await store.send(.recordingFailed("マイクにアクセスできません")) {
            $0.recordingStatus = .idle
            $0.errorMessage = "マイクにアクセスできません"
        }
    }

    // MARK: - 異常系: 録音開始失敗

    /// 録音開始時にエラーが発生した場合、recordingFailedが受信される
    func test_recordButtonTapped_録音開始失敗_recordingFailedが受信される() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.startRecording = { throw RecordingError.microphonePermissionDenied }
            $0.customDictionaryClient.getContextualStrings = { [] }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: recordButtonTapped が startTimerEffect（ImmediateClockで即座にtimerTicked発火）と
        // startRecordingEffect を .merge で起動し、timerTicked と recordingFailed の受信順序が非決定的なため解消困難
        store.exhaustivity = .off

        await store.send(.recordButtonTapped) {
            $0.recordingStatus = .recording
            $0.elapsedTime = 0
            $0.errorMessage = nil
        }

        await store.receive(\.recordingFailed) {
            $0.recordingStatus = .idle
            $0.errorMessage = RecordingError.microphonePermissionDenied.localizedDescription
        }
    }

    // MARK: - 正常系: 完了画面 → viewMemoTapped

    /// 完了画面で「メモを見る」タップ → idle状態にリセットしnavigateToMemoDetailを送信する
    func test_viewMemoTapped_saved状態_idleにリセットしnavigateToMemoDetailを送信する() async {
        let memoID = UUID()
        let memo = VoiceMemoEntity(
            id: memoID,
            title: "テストメモ",
            audioFilePath: "/Documents/Audio/test.m4a",
            transcription: TranscriptionEntity(
                fullText: "テスト文字起こし",
                language: "ja-JP",
                confidence: 0.9
            )
        )

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .saved(memo),
                elapsedTime: 10.0,
                partialTranscription: "テスト文字起こし",
                confirmedTranscription: "テスト文字起こし",
                isPermissionGranted: true,
                wasAutoStopped: true,
                aiProcessingCompleted: true
            )
        ) {
            RecordingFeature()
        }

        await store.send(.viewMemoTapped) {
            $0.recordingStatus = .idle
            $0.partialTranscription = ""
            $0.confirmedTranscription = ""
            $0.elapsedTime = 0
            $0.audioLevel = 0
            $0.wasAutoStopped = false
            $0.aiProcessingCompleted = false
        }

        await store.receive(.navigateToMemoDetail(memoID))
    }

    // MARK: - 正常系: 完了画面 → dismissCompletion

    /// 完了画面で「あとで」タップ → idle状態にリセットし録音画面に戻る
    func test_dismissCompletion_saved状態_idleにリセットする() async {
        let memo = VoiceMemoEntity(
            id: UUID(),
            title: "テストメモ",
            audioFilePath: "/Documents/Audio/test.m4a"
        )

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .saved(memo),
                elapsedTime: 5.0,
                partialTranscription: "テスト",
                confirmedTranscription: "テスト",
                isPermissionGranted: true,
                wasAutoStopped: true,
                aiProcessingCompleted: true
            )
        ) {
            RecordingFeature()
        }

        await store.send(.dismissCompletion) {
            $0.recordingStatus = .idle
            $0.partialTranscription = ""
            $0.confirmedTranscription = ""
            $0.elapsedTime = 0
            $0.audioLevel = 0
            $0.wasAutoStopped = false
            $0.aiProcessingCompleted = false
        }
    }

    /// idle状態でviewMemoTappedしても何も起きない
    func test_viewMemoTapped_idle状態_何も起きない() async {
        let store = TestStore(
            initialState: RecordingFeature.State(isPermissionGranted: true)
        ) {
            RecordingFeature()
        }

        await store.send(.viewMemoTapped)
    }

    // MARK: - aiProcessingCompleted

    /// aiProcessingCompletedの初期値がfalseであること
    func test_aiProcessingCompleted_初期値がfalseであること() {
        let state = RecordingFeature.State()
        XCTAssertEqual(state.aiProcessingCompleted, false)
    }

    // MARK: - 正常系: timerTicked → 最大時間到達で自動停止

    // MARK: - CompletionStage Comparable

    /// CompletionStageの順序がinitial < checkmark < preview < ctaであること
    func test_completionStage_順序がinitial_checkmark_preview_ctaであること() {
        let stages: [RecordingFeature.State.CompletionStage] = [.initial, .checkmark, .preview, .cta]
        for i in 0..<stages.count - 1 {
            XCTAssertLessThan(stages[i], stages[i + 1])
        }
    }

    // MARK: - 正常系: timerTicked → 最大時間到達で自動停止

    /// 最大録音時間に到達した場合、wasAutoStoppedがtrueになりstopButtonTappedが送信される
    func test_timerTicked_最大時間到達_wasAutoStoppedがtrueになりstopButtonTappedが送信される() async {
        let recordingResult = RecordingResult(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 300.0,
            format: .m4a
        )

        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .recording,
                elapsedTime: 299,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.stopRecording = { recordingResult }
            $0.sttEngine.finishTranscription = {
                TranscriptionResult(text: "", confidence: 0.0, isFinal: true, language: "ja-JP")
            }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { _ in }
            $0.temporaryRecordingStore.cleanup = { _ in }
            $0.continuousClock = ImmediateClock()
        }
        // exhaustivity = .off: timerTicked → stopButtonTapped → finalizeSttEffect → sttFinalized → saveRecordingEffect の
        // 一連のエフェクトが発生し、保存完了後の completionStageAdvanced 等を全て追跡するのが困難なため
        store.exhaustivity = .off

        await store.send(.timerTicked) {
            $0.elapsedTime = 300
            $0.wasAutoStopped = true
        }

        await store.receive(\.stopButtonTapped)
    }
}
