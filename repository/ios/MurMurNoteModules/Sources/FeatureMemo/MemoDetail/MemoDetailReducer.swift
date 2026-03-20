import ComposableArchitecture
import Domain
import Foundation

/// メモ詳細画面のTCA Reducer
/// TASK-0012: メモ詳細画面
/// 設計書 01-system-architecture.md セクション2.2 準拠
@Reducer
public struct MemoDetailReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public let memoID: UUID
        public var title: String = ""
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var durationSeconds: Double = 0
        public var audioFilePath: String = ""

        // 文字起こし
        public var transcriptionText: String = ""
        public var transcriptionLanguage: String = "ja-JP"
        public var transcriptionConfidence: Double = 0

        // AI要約（Phase 3で実装、枠のみ）
        public var aiSummary: AISummaryState?
        public var isAISummaryAvailable: Bool = false

        // 感情分析
        public var emotion: EmotionState?

        // タグ
        public var tags: [TagItem] = []

        // 子Reducer State
        public var editState: MemoEditReducer.State?
        public var deleteState: MemoDeleteReducer.State = .init()
        public var audioPlayer: AudioPlayerReducer.State?

        // AI処理ステータス
        public var aiProcessingStatus: AIProcessingStatus = .idle

        // UI状態
        public var isLoading: Bool = false
        public var errorMessage: String?
        public var showDeleteConfirmation: Bool = false

        public init(
            memoID: UUID,
            title: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            durationSeconds: Double = 0,
            audioFilePath: String = "",
            transcriptionText: String = "",
            transcriptionLanguage: String = "ja-JP",
            transcriptionConfidence: Double = 0,
            aiSummary: AISummaryState? = nil,
            isAISummaryAvailable: Bool = false,
            emotion: EmotionState? = nil,
            tags: [TagItem] = [],
            editState: MemoEditReducer.State? = nil,
            deleteState: MemoDeleteReducer.State = .init(),
            audioPlayer: AudioPlayerReducer.State? = nil,
            aiProcessingStatus: AIProcessingStatus = .idle,
            isLoading: Bool = false,
            errorMessage: String? = nil,
            showDeleteConfirmation: Bool = false
        ) {
            self.memoID = memoID
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.durationSeconds = durationSeconds
            self.audioFilePath = audioFilePath
            self.transcriptionText = transcriptionText
            self.transcriptionLanguage = transcriptionLanguage
            self.transcriptionConfidence = transcriptionConfidence
            self.aiSummary = aiSummary
            self.isAISummaryAvailable = isAISummaryAvailable
            self.emotion = emotion
            self.tags = tags
            self.editState = editState
            self.deleteState = deleteState
            self.audioPlayer = audioPlayer
            self.aiProcessingStatus = aiProcessingStatus
            self.isLoading = isLoading
            self.errorMessage = errorMessage
            self.showDeleteConfirmation = showDeleteConfirmation
        }

        // MARK: - Nested Types

        public struct AISummaryState: Equatable, Sendable {
            public var summaryText: String
            public var keyPoints: [String]
            public var providerType: String
            public var isOnDevice: Bool
            public var generatedAt: Date

            public init(
                summaryText: String,
                keyPoints: [String] = [],
                providerType: String = "",
                isOnDevice: Bool = true,
                generatedAt: Date = Date()
            ) {
                self.summaryText = summaryText
                self.keyPoints = keyPoints
                self.providerType = providerType
                self.isOnDevice = isOnDevice
                self.generatedAt = generatedAt
            }
        }

        public struct EmotionState: Equatable, Sendable {
            public var category: EmotionCategory
            public var confidence: Double
            public var emotionDescription: String

            public init(
                category: EmotionCategory,
                confidence: Double,
                emotionDescription: String
            ) {
                self.category = category
                self.confidence = confidence
                self.emotionDescription = emotionDescription
            }
        }

        public struct TagItem: Equatable, Identifiable, Sendable {
            public let id: UUID
            public var name: String
            public var source: String

            public init(id: UUID, name: String, source: String) {
                self.id = id
                self.name = name
                self.source = source
            }
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear
        case memoLoaded(Result<MemoDetail, EquatableError>)
        case editButtonTapped
        case deleteButtonTapped
        case deleteConfirmationPresented(Bool)
        case tagTapped(String)
        case shareButtonTapped
        case backButtonTapped
        case regenerateAISummary
        case aiProcessingStatusUpdated(AIProcessingStatus)

        // 子Reducerアクション
        case edit(MemoEditReducer.Action)
        case delete(MemoDeleteReducer.Action)
        case audioPlayer(AudioPlayerReducer.Action)

        // 編集シート制御
        case dismissEditSheet
        /// 削除完了後にAppReducerに伝播するアクション
        case _deleteCompletedAndDismiss(UUID)
        /// 編集保存完了後にメモ詳細をリロードするアクション
        case _editSavedAndReload
    }

    /// ロードしたメモの詳細データ
    public struct MemoDetail: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let createdAt: Date
        public let updatedAt: Date
        public let durationSeconds: Double
        public let audioFilePath: String
        public let transcriptionText: String
        public let transcriptionLanguage: String
        public let transcriptionConfidence: Double
        public let aiSummary: State.AISummaryState?
        public let emotion: State.EmotionState?
        public let tags: [State.TagItem]

        public init(
            id: UUID,
            title: String,
            createdAt: Date,
            updatedAt: Date,
            durationSeconds: Double,
            audioFilePath: String,
            transcriptionText: String,
            transcriptionLanguage: String,
            transcriptionConfidence: Double,
            aiSummary: State.AISummaryState?,
            emotion: State.EmotionState?,
            tags: [State.TagItem]
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.durationSeconds = durationSeconds
            self.audioFilePath = audioFilePath
            self.transcriptionText = transcriptionText
            self.transcriptionLanguage = transcriptionLanguage
            self.transcriptionConfidence = transcriptionConfidence
            self.aiSummary = aiSummary
            self.emotion = emotion
            self.tags = tags
        }
    }

    // MARK: - Cancellation IDs

    private enum CancelID {
        case aiObserve
    }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.aiProcessingQueue) var aiProcessingQueue

    public init() {}

    // MARK: - Reducer Body

    public var body: some ReducerOf<Self> {
        Scope(state: \.deleteState, action: \.delete) {
            MemoDeleteReducer()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                let memoID = state.memoID
                return .merge(
                    .run { send in
                        let result = await Result {
                            try await self.loadDetail(memoID: memoID)
                        }.mapError { EquatableError($0) }
                        await send(.memoLoaded(result))
                    },
                    .run { send in
                        for await status in self.aiProcessingQueue.observeStatus(memoID) {
                            await send(.aiProcessingStatusUpdated(status))
                        }
                    }
                    .cancellable(id: CancelID.aiObserve, cancelInFlight: true)
                )

            case let .memoLoaded(.success(detail)):
                state.isLoading = false
                state.title = detail.title
                state.createdAt = detail.createdAt
                state.updatedAt = detail.updatedAt
                state.durationSeconds = detail.durationSeconds
                state.audioFilePath = detail.audioFilePath
                state.transcriptionText = detail.transcriptionText
                state.transcriptionLanguage = detail.transcriptionLanguage
                state.transcriptionConfidence = detail.transcriptionConfidence
                state.aiSummary = detail.aiSummary
                state.isAISummaryAvailable = detail.aiSummary != nil
                state.emotion = detail.emotion
                state.tags = detail.tags

                // 音声プレイヤーの初期化（音声ファイルが存在する場合）
                if !detail.audioFilePath.isEmpty {
                    state.audioPlayer = AudioPlayerReducer.State(
                        audioFilePath: detail.audioFilePath
                    )
                }
                return .none

            case let .memoLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            // MARK: - 編集ボタン → MemoEditView をシート表示
            case .editButtonTapped:
                state.editState = MemoEditReducer.State(
                    memoID: state.memoID,
                    title: state.title,
                    transcriptionText: state.transcriptionText,
                    originalTitle: state.title,
                    originalTranscriptionText: state.transcriptionText
                )
                return .none

            case .dismissEditSheet:
                // キャンセルは MemoEditReducer.onDisappear が自身で処理するため、
                // 親から子の内部IDを直接キャンセルする必要はない（#14: 親漏洩解消）
                state.editState = nil
                return .none

            // MARK: - 編集保存完了 → タイトル反映 + リロード（シートは閉じない）
            // シートはユーザーが「閉じる」を押した時（dismissEditSheet）でのみ閉じる。
            // ここで editState = nil にすると、SwiftUIのアニメーション中に
            // バインディングが .titleChanged を送信し ifLet 警告が出るため。
            case .edit(.saveCompleted(.success)):
                if let editState = state.editState {
                    state.title = editState.title
                    state.transcriptionText = editState.transcriptionText
                }
                return .send(._editSavedAndReload)

            case ._editSavedAndReload:
                // メモ詳細を再読み込み
                state.isLoading = true
                let memoID = state.memoID
                return .run { send in
                    let result = await Result {
                        try await self.loadDetail(memoID: memoID)
                    }.mapError { EquatableError($0) }
                    await send(.memoLoaded(result))
                }

            case .edit(.discardConfirmed):
                // キャンセルは MemoEditReducer.discardConfirmed が自身で処理する（#14: 親漏洩解消）
                state.editState = nil
                return .none

            case .edit:
                // editState が nil の場合（シート閉じ後のバインディング遅延）は無視
                return .none

            // MARK: - 削除ボタン → 確認ダイアログ表示
            case .deleteButtonTapped:
                state.showDeleteConfirmation = true
                return .none

            case let .deleteConfirmationPresented(isPresented):
                state.showDeleteConfirmation = isPresented
                if !isPresented {
                    // キャンセルされた場合
                    return .send(.delete(.deleteCancelled))
                }
                return .none

            // MARK: - 削除完了 → AppReducerに伝播して一覧に戻る
            case let .delete(.deleteCompleted(.success(deletedID))):
                return .send(._deleteCompletedAndDismiss(deletedID))

            case .delete:
                return .none

            case ._deleteCompletedAndDismiss:
                // AppReducerで処理される
                return .none

            case let .aiProcessingStatusUpdated(status):
                state.aiProcessingStatus = status
                if case .completed = status {
                    // AI処理完了時はメモ詳細を再読み込み
                    let memoID = state.memoID
                    return .run { send in
                        let result = await Result {
                            try await self.loadDetail(memoID: memoID)
                        }.mapError { EquatableError($0) }
                        await send(.memoLoaded(result))
                    }
                }
                return .none

            case .tagTapped, .shareButtonTapped, .backButtonTapped, .regenerateAISummary:
                return .none

            case .audioPlayer:
                return .none
            }
        }
        .ifLet(\.editState, action: \.edit) {
            MemoEditReducer()
        }
        .ifLet(\.audioPlayer, action: \.audioPlayer) {
            AudioPlayerReducer()
        }
    }

    // MARK: - Helpers

    private func loadDetail(memoID: UUID) async throws -> MemoDetail {
        let entity = try await voiceMemoRepository.fetchMemoDetail(memoID)
        return MemoDetail(
            id: entity.id,
            title: entity.title,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            durationSeconds: entity.durationSeconds,
            audioFilePath: entity.audioFilePath,
            transcriptionText: entity.transcription?.fullText ?? "",
            transcriptionLanguage: entity.transcription?.language ?? "ja-JP",
            transcriptionConfidence: entity.transcription?.confidence ?? 0,
            aiSummary: entity.aiSummary.map { summary in
                State.AISummaryState(
                    summaryText: summary.summaryText,
                    keyPoints: summary.keyPoints,
                    providerType: summary.providerType.rawValue,
                    isOnDevice: summary.isOnDevice,
                    generatedAt: summary.generatedAt
                )
            },
            emotion: entity.emotionAnalysis.map { analysis in
                State.EmotionState(
                    category: analysis.primaryEmotion,
                    confidence: analysis.confidence,
                    emotionDescription: "感情分析結果"
                )
            },
            tags: entity.tags.map { tag in
                State.TagItem(
                    id: tag.id,
                    name: tag.name,
                    source: tag.source.rawValue
                )
            }
        )
    }
}
