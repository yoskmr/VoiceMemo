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
            $0.continuousClock = ImmediateClock()
        }
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

    /// 録音中に一時停止ボタンタップ → pausedに遷移する
    func test_pauseButtonTapped_recording中_pausedに遷移する() async {
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

    // MARK: - 正常系: resumeButtonTapped → recording状態

    /// 一時停止中に再開ボタンタップ → recordingに遷移する
    func test_resumeButtonTapped_paused中_recordingに遷移する() async {
        let store = TestStore(
            initialState: RecordingFeature.State(
                recordingStatus: .paused,
                isPermissionGranted: true
            )
        ) {
            RecordingFeature()
        } withDependencies: {
            $0.audioRecorder.resumeRecording = {}
        }

        await store.send(.resumeButtonTapped) {
            $0.recordingStatus = .recording
        }
    }

    // MARK: - 正常系: stopButtonTapped → saving → 保存完了

    /// 録音中に停止ボタンタップ → savingに遷移し保存完了アクションを受信する
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
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { memo in savedMemos.withValue { $0.append(memo) } }
            $0.temporaryRecordingStore.cleanup = { _ in }
        }

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        await store.receive(\.recordingSaved) {
            $0.recordingStatus = .idle
            $0.partialTranscription = ""
            $0.confirmedTranscription = ""
            $0.elapsedTime = 0
            $0.audioLevel = 0
        }

        // VoiceMemoが正しく保存されたことを確認
        savedMemos.withValue { memos in
            XCTAssertEqual(memos.count, 1)
            XCTAssertEqual(memos.first?.id, recordingID)
            XCTAssertEqual(memos.first?.durationSeconds, 10.0)
            XCTAssertEqual(memos.first?.transcription?.fullText, "テスト文字起こし")
        }
    }

    /// 録音停止時にSTT確定が失敗しても空のTranscriptionで保存される
    func test_stopButtonTapped_STT失敗時_空のTranscriptionで保存される() async {
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
                throw NSError(domain: "STT", code: -1, userInfo: nil)
            }
            $0.audioFileStore.moveToDocuments = { _, id in
                URL(fileURLWithPath: "/Documents/Audio/\(id.uuidString).m4a")
            }
            $0.audioFileStore.setFileProtection = { _ in }
            $0.voiceMemoRepository.save = { memo in savedMemos.withValue { $0.append(memo) } }
            $0.temporaryRecordingStore.cleanup = { _ in }
        }

        await store.send(.stopButtonTapped) {
            $0.recordingStatus = .saving
        }

        await store.receive(\.recordingSaved) {
            $0.recordingStatus = .idle
            $0.partialTranscription = ""
            $0.confirmedTranscription = ""
            $0.elapsedTime = 0
            $0.audioLevel = 0
        }

        // STT失敗時でも空のTranscriptionで保存される
        savedMemos.withValue { memos in
            XCTAssertEqual(memos.count, 1)
            XCTAssertEqual(memos.first?.transcription?.fullText, "")
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
            $0.continuousClock = ImmediateClock()
        }
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
            $0.continuousClock = ImmediateClock()
        }
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
}
