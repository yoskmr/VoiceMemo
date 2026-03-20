import Dependencies
import Foundation

/// 録音完了時の保存フロー全体を管理するユースケース
/// 01-Arch セクション4.1 準拠:
/// 録音停止 → STT確定 → ファイル移動 → 保護レベル設定 → SwiftData保存 → 一時ファイル削除
public struct SaveRecordingUseCase: Sendable {
    /// 録音保存の入力パラメータ
    public struct Input: Sendable, Equatable {
        public let recordingID: UUID
        public let tempAudioURL: URL
        public let durationSeconds: Double
        public let transcriptionResult: TranscriptionResult

        public init(
            recordingID: UUID,
            tempAudioURL: URL,
            durationSeconds: Double,
            transcriptionResult: TranscriptionResult
        ) {
            self.recordingID = recordingID
            self.tempAudioURL = tempAudioURL
            self.durationSeconds = durationSeconds
            self.transcriptionResult = transcriptionResult
        }
    }

    /// 録音保存の出力
    public struct Output: Sendable, Equatable {
        public let memoID: UUID
        public let memo: VoiceMemoEntity

        public init(memoID: UUID, memo: VoiceMemoEntity) {
            self.memoID = memoID
            self.memo = memo
        }
    }

    // MARK: - Dependencies

    private let audioFileStore: AudioFileStoreClient
    private let voiceMemoRepository: VoiceMemoRepositoryClient
    private let temporaryRecordingStore: TemporaryRecordingStoreClient

    public init(
        audioFileStore: AudioFileStoreClient,
        voiceMemoRepository: VoiceMemoRepositoryClient,
        temporaryRecordingStore: TemporaryRecordingStoreClient
    ) {
        self.audioFileStore = audioFileStore
        self.voiceMemoRepository = voiceMemoRepository
        self.temporaryRecordingStore = temporaryRecordingStore
    }

    // MARK: - Execute

    /// 録音完了フローを実行する
    /// - Parameter input: 録音保存の入力パラメータ
    /// - Returns: 保存されたメモの情報
    /// - Throws: `SaveRecordingError`
    public func execute(_ input: Input) async throws -> Output {
        // 1. 音声ファイルをDocuments/Audio/に移動
        let permanentURL: URL
        do {
            permanentURL = try await audioFileStore.moveToDocuments(input.tempAudioURL, input.recordingID)
        } catch {
            throw SaveRecordingError.fileMoveFailed(error.localizedDescription)
        }

        // 2. NSFileProtectionComplete適用
        do {
            try audioFileStore.setFileProtection(permanentURL)
        } catch {
            throw SaveRecordingError.fileProtectionFailed(error.localizedDescription)
        }

        // 3. VoiceMemo + Transcription エンティティ作成
        let transcription = TranscriptionEntity(
            fullText: input.transcriptionResult.text,
            language: input.transcriptionResult.language,
            engineType: .whisperKit,
            confidence: input.transcriptionResult.confidence
        )

        let memo = VoiceMemoEntity(
            id: input.recordingID,
            title: "",
            durationSeconds: input.durationSeconds,
            audioFilePath: "Audio/\(input.recordingID.uuidString).m4a",
            audioFormat: .m4a,
            status: .completed,
            transcription: transcription
        )

        // 4. SwiftData保存
        do {
            try await voiceMemoRepository.save(memo)
        } catch {
            throw SaveRecordingError.persistenceFailed(error.localizedDescription)
        }

        // 5. 一時ファイル削除（非致命的 - 失敗してもメモ保存は成功とする）
        do {
            try temporaryRecordingStore.cleanup(input.recordingID)
        } catch {
            // クリーンアップ失敗はログのみ（メモ保存自体は成功）
        }

        return Output(memoID: memo.id, memo: memo)
    }
}

// MARK: - DependencyKey

extension SaveRecordingUseCase: DependencyKey {
    public static var liveValue: SaveRecordingUseCase {
        @Dependency(\.audioFileStore) var audioFileStore
        @Dependency(\.voiceMemoRepository) var voiceMemoRepository
        @Dependency(\.temporaryRecordingStore) var temporaryRecordingStore
        return SaveRecordingUseCase(
            audioFileStore: audioFileStore,
            voiceMemoRepository: voiceMemoRepository,
            temporaryRecordingStore: temporaryRecordingStore
        )
    }

    public static var testValue: SaveRecordingUseCase {
        @Dependency(\.audioFileStore) var audioFileStore
        @Dependency(\.voiceMemoRepository) var voiceMemoRepository
        @Dependency(\.temporaryRecordingStore) var temporaryRecordingStore
        return SaveRecordingUseCase(
            audioFileStore: audioFileStore,
            voiceMemoRepository: voiceMemoRepository,
            temporaryRecordingStore: temporaryRecordingStore
        )
    }
}

extension DependencyValues {
    public var saveRecordingUseCase: SaveRecordingUseCase {
        get { self[SaveRecordingUseCase.self] }
        set { self[SaveRecordingUseCase.self] = newValue }
    }
}
