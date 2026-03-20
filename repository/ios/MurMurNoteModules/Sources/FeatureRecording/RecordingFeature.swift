import ComposableArchitecture
import Domain
import Foundation

/// 録音画面のTCA Feature
/// 設計書01-system-architecture.md セクション2.2 準拠
/// @Dependency でAudioRecorderとSTTEngineを注入（Infra直接依存禁止）
@Reducer
public struct RecordingFeature {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        /// 録音セッションを識別するUUID
        public var recordingID: UUID
        /// 録音の状態（idle / recording / paused / saving）
        public var recordingStatus: RecordingStatus = .idle
        /// 録音経過時間（秒）
        public var elapsedTime: TimeInterval = 0
        /// リアルタイム文字起こしテキスト（部分結果）
        public var partialTranscription: String = ""
        /// 確定済みテキスト（isFinalで蓄積される）
        public var confirmedTranscription: String = ""
        /// 音声レベル（0.0 - 1.0、波形表示用）
        public var audioLevel: Float = 0
        /// 文字起こし信頼度レベル
        public var confidenceLevel: ConfidenceLevel = .high
        /// マイク・音声認識権限が許可済みか
        public var isPermissionGranted: Bool = false
        /// エラーメッセージ（nil = エラーなし）
        public var errorMessage: String?

        public init(
            recordingID: UUID = UUID(),
            recordingStatus: RecordingStatus = .idle,
            elapsedTime: TimeInterval = 0,
            partialTranscription: String = "",
            confirmedTranscription: String = "",
            audioLevel: Float = 0,
            confidenceLevel: ConfidenceLevel = .high,
            isPermissionGranted: Bool = false,
            errorMessage: String? = nil
        ) {
            self.recordingID = recordingID
            self.recordingStatus = recordingStatus
            self.elapsedTime = elapsedTime
            self.partialTranscription = partialTranscription
            self.confirmedTranscription = confirmedTranscription
            self.audioLevel = audioLevel
            self.confidenceLevel = confidenceLevel
            self.isPermissionGranted = isPermissionGranted
            self.errorMessage = errorMessage
        }

        /// 録音状態
        public enum RecordingStatus: Equatable, Sendable {
            case idle
            case recording
            case paused
            /// 保存処理中
            case saving
            /// 保存完了（完了画面表示中）
            case saved(VoiceMemoEntity)
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        // ユーザーアクション
        case recordButtonTapped
        case pauseButtonTapped
        case resumeButtonTapped
        case stopButtonTapped
        case permissionRequested
        case permissionResponse(Bool)

        // 完了画面アクション
        case viewMemoTapped
        case dismissCompletion
        /// 親（AppReducer）にメモ詳細への遷移を通知
        case navigateToMemoDetail(UUID)

        // 内部アクション（Effect からの通知）
        case timerTicked
        case audioLevelUpdated(Float)
        case transcriptionUpdated(String, Double, Bool)  // text, confidence, isFinal
        case recordingCompleted(URL)                // 音声ファイルURL
        case recordingSaved(VoiceMemoEntity)        // 保存完了
        case recordingFailed(String)                // エラーメッセージ
    }

    // MARK: - Dependencies

    @Dependency(\.audioRecorder) var audioRecorder
    @Dependency(\.sttEngine) var sttEngine
    @Dependency(\.saveRecordingUseCase) var saveRecordingUseCase
    @Dependency(\.continuousClock) var clock

    // MARK: - Cancellation IDs

    private enum CancelID {
        case timer
        case recording
        case audioLevel
    }

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .recordButtonTapped:
                guard state.isPermissionGranted else {
                    return .send(.permissionRequested)
                }
                state.recordingID = UUID()
                state.recordingStatus = .recording
                state.elapsedTime = 0
                state.partialTranscription = ""
                state.confirmedTranscription = ""
                state.errorMessage = nil
                return .merge(
                    startRecordingEffect(),
                    startTimerEffect()
                )

            case .pauseButtonTapped:
                state.recordingStatus = .paused
                return .merge(
                    .cancel(id: CancelID.timer),
                    .run { send in
                        do {
                            try await audioRecorder.pauseRecording()
                        } catch {
                            await send(.recordingFailed(error.localizedDescription))
                        }
                    }
                )

            case .resumeButtonTapped:
                state.recordingStatus = .recording
                return .merge(
                    startTimerEffect(),
                    .run { send in
                        do {
                            try await audioRecorder.resumeRecording()
                        } catch {
                            await send(.recordingFailed(error.localizedDescription))
                        }
                    }
                )

            case .stopButtonTapped:
                state.recordingStatus = .saving
                // UIに表示中のテキストを保存用に確保（STTのfinishに頼らない）
                let currentTranscription = state.partialTranscription
                return .merge(
                    .cancel(id: CancelID.timer),
                    .cancel(id: CancelID.audioLevel),
                    stopAndSaveEffect(
                        recordingID: state.recordingID,
                        elapsedTime: state.elapsedTime,
                        transcriptionText: currentTranscription
                    )
                )

            case .permissionRequested:
                return .run { send in
                    let granted = await audioRecorder.requestPermission()
                    await send(.permissionResponse(granted))
                }

            case let .permissionResponse(granted):
                state.isPermissionGranted = granted
                if granted {
                    // 権限許可後、自動的に録音を開始
                    return .send(.recordButtonTapped)
                }
                return .none

            case .timerTicked:
                state.elapsedTime += 1
                return .none

            case let .audioLevelUpdated(level):
                state.audioLevel = level
                return .none

            case let .transcriptionUpdated(text, confidence, isFinal):
                if isFinal {
                    // このセッションのテキストを確定して蓄積
                    state.confirmedTranscription += text + " "
                    state.partialTranscription = state.confirmedTranscription
                } else {
                    // 現在のセッションテキスト（confirmed以降の部分）
                    let currentSessionText = String(state.partialTranscription.dropFirst(state.confirmedTranscription.count))

                    // Apple Speechがテキストをリセットした検出:
                    // 新テキストが現セッションテキストより大幅に短い場合
                    if !text.isEmpty && currentSessionText.count >= 4 && text.count < currentSessionText.count / 2 {
                        // 前のセッションテキストを確定に追加
                        state.confirmedTranscription += currentSessionText + " "
                        print("[Reducer] リセット検出: 確定='\(currentSessionText.prefix(20))...' 新='\(text.prefix(10))...'")
                    }

                    state.partialTranscription = state.confirmedTranscription + text
                }
                state.confidenceLevel = ConfidenceLevel(confidence: confidence)
                return .none

            case .recordingCompleted:
                // 後方互換: 旧テストで使用
                return .none

            case let .recordingSaved(memo):
                // 完了画面を表示（リセットはviewMemoTapped/dismissCompletionで行う）
                state.recordingStatus = .saved(memo)
                return .none

            case .viewMemoTapped:
                guard case let .saved(memo) = state.recordingStatus else {
                    return .none
                }
                let memoID = memo.id
                // 状態をリセット
                state.recordingStatus = .idle
                state.partialTranscription = ""
                state.confirmedTranscription = ""
                state.elapsedTime = 0
                state.audioLevel = 0
                return .send(.navigateToMemoDetail(memoID))

            case .dismissCompletion:
                // 状態をリセットして録音画面に戻る
                state.recordingStatus = .idle
                state.partialTranscription = ""
                state.confirmedTranscription = ""
                state.elapsedTime = 0
                state.audioLevel = 0
                return .none

            case .navigateToMemoDetail:
                // 親Reducer（AppReducer）で処理する
                return .none

            case let .recordingFailed(message):
                state.recordingStatus = .idle
                state.errorMessage = message
                return .merge(
                    .cancel(id: CancelID.timer),
                    .cancel(id: CancelID.audioLevel)
                )
            }
        }
    }

    // MARK: - Effects

    private func startRecordingEffect() -> Effect<Action> {
        .run { send in
            let (levelStream, pcmStream) = try await audioRecorder.startRecording()

            // STTエンジン起動（PCMバッファを渡す）
            let transcriptionStream = sttEngine.startTranscription(pcmStream, "ja-JP")

            // 3つのストリームを並行監視
            await withTaskGroup(of: Void.self) { group in
                // 音声レベル監視
                group.addTask {
                    for await levelUpdate in levelStream {
                        let normalized = self.normalizeAudioLevel(levelUpdate.averagePower)
                        await send(.audioLevelUpdated(normalized))
                    }
                }
                // 文字起こし監視（isFinalフラグを伝達）
                group.addTask {
                    for await result in transcriptionStream {
                        await send(.transcriptionUpdated(result.text, result.confidence, result.isFinal))
                    }
                }
            }
        } catch: { error, send in
            await send(.recordingFailed(error.localizedDescription))
        }
        .cancellable(id: CancelID.audioLevel)
    }

    private func startTimerEffect() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(1)) {
                await send(.timerTicked)
            }
        }
        .cancellable(id: CancelID.timer)
    }

    /// 録音停止 → 保存の一連フロー
    /// transcriptionTextはUIに表示中のテキストを直接使う（STTのfinishに頼らない）
    private func stopAndSaveEffect(
        recordingID: UUID,
        elapsedTime: TimeInterval,
        transcriptionText: String
    ) -> Effect<Action> {
        .run { send in
            // 1. 録音停止
            let result = try await audioRecorder.stopRecording()

            // 2. UIに表示されていたテキストでTranscriptionResultを作成
            let transcriptionResult = TranscriptionResult(
                text: transcriptionText,
                confidence: 0.8,
                isFinal: true,
                language: "ja-JP",
                segments: []
            )

            // 3. SaveRecordingUseCase実行
            let input = SaveRecordingUseCase.Input(
                recordingID: recordingID,
                tempAudioURL: result.fileURL,
                durationSeconds: elapsedTime,
                transcriptionResult: transcriptionResult
            )
            let output = try await saveRecordingUseCase.execute(input)
            await send(.recordingSaved(output.memo))
        } catch: { error, send in
            await send(.recordingFailed(error.localizedDescription))
        }
    }

    // MARK: - Helpers

    /// dBレベルを0.0-1.0に正規化する
    private func normalizeAudioLevel(_ dB: Float) -> Float {
        // -160 dB (silence) → 0.0, 0 dB (max) → 1.0
        let minDB: Float = -60
        let maxDB: Float = 0
        let clampedDB = min(max(dB, minDB), maxDB)
        return (clampedDB - minDB) / (maxDB - minDB)
    }
}

// MARK: - ConfidenceLevel

/// 文字起こし信頼度レベル
public enum ConfidenceLevel: Equatable, Sendable {
    case high    // 0.7以上
    case medium  // 0.4以上
    case low     // 0.4未満

    public init(confidence: Double) {
        if confidence >= 0.7 {
            self = .high
        } else if confidence >= 0.4 {
            self = .medium
        } else {
            self = .low
        }
    }
}
