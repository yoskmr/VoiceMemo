import ComposableArchitecture
import Domain
import Foundation
import SharedUtil

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

        // AI クォータ情報（T09: AI処理連携拡張）
        public var remainingQuota: Int = 15
        public var quotaLimit: Int = 15

        // AI要約 UI 状態（T10: AI要約・タグUI実体化）
        public var isSummaryExpanded: Bool = false

        // AIオンボーディング表示フラグ
        public var showAIOnboarding: Bool = false

        // AIフィードバック（このメモへの既存フィードバック）
        public var aiFeedback: AIFeedback?

        // 辞書レコメンド
        public var dictionaryRecommendation: DictionaryRecommendation?
        /// 編集差分検出用: メモロード時の文字起こしテキスト原文
        public var originalTranscriptionText: String?

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
            remainingQuota: Int = 15,
            quotaLimit: Int = 15,
            isSummaryExpanded: Bool = false,
            showAIOnboarding: Bool = false,
            aiFeedback: AIFeedback? = nil,
            dictionaryRecommendation: DictionaryRecommendation? = nil,
            originalTranscriptionText: String? = nil,
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
            self.remainingQuota = remainingQuota
            self.quotaLimit = quotaLimit
            self.isSummaryExpanded = isSummaryExpanded
            self.showAIOnboarding = showAIOnboarding
            self.aiFeedback = aiFeedback
            self.dictionaryRecommendation = dictionaryRecommendation
            self.originalTranscriptionText = originalTranscriptionText
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
        /// AI要約カードの展開/折りたたみトグル（T10）
        case toggleSummaryExpanded
        /// AI分析を手動トリガーする（未生成時のプレースホルダからの呼び出し）
        case triggerAIProcessing
        /// AIオンボーディングを閉じた → フラグ保存 → AI処理実行
        case aiOnboardingDismissed
        /// クォータ情報の受信（T09）
        case _quotaInfoLoaded(remaining: Int, limit: Int)

        /// AIフィードバック
        case aiFeedbackTapped(isPositive: Bool)
        case aiFeedbackSaved

        /// 辞書レコメンド
        case checkDictionaryRecommendations
        case dictionaryRecommendationLoaded(DictionaryRecommendation?)
        case acceptDictionaryRecommendation(DictionaryRecommendation)
        case dismissDictionaryRecommendation(DictionaryRecommendation)

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
    @Dependency(\.aiQuota) var aiQuota
    @Dependency(\.customDictionaryClient) var customDictionaryClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.analyticsClient) var analyticsClient

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
                    .cancellable(id: CancelID.aiObserve, cancelInFlight: true),
                    // T09: クォータ情報をロード
                    .run { send in
                        let remaining = try await self.aiQuota.remainingCount()
                        let limit = self.aiQuota.monthlyLimit()
                        await send(._quotaInfoLoaded(remaining: remaining, limit: limit))
                    } catch: { _, _ in
                        // クォータ取得失敗は無視（デフォルト値が表示される）
                    }
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

                // 編集差分検出用に文字起こし原文を保存
                state.originalTranscriptionText = detail.transcriptionText

                // 既存のAIフィードバックを読み込み
                state.aiFeedback = AIFeedbackStore.feedbackForMemo(detail.id)

                // 音声プレイヤーの初期化（音声ファイルが存在する場合）
                if !detail.audioFilePath.isEmpty {
                    state.audioPlayer = AudioPlayerReducer.State(
                        audioFilePath: detail.audioFilePath
                    )
                }
                analyticsClient.send("memo.viewed")
                return .send(.checkDictionaryRecommendations)

            case let .memoLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            // MARK: - 編集ボタン → MemoEditView をシート表示
            // 編集対象はAI整理テキスト（あれば）、なければ元の文字起こし
            case .editButtonTapped:
                let editText = state.aiSummary?.summaryText ?? state.transcriptionText
                state.editState = MemoEditReducer.State(
                    memoID: state.memoID,
                    title: state.title,
                    transcriptionText: editText,
                    originalTitle: state.title,
                    originalTranscriptionText: editText
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
                    // 編集前後の差分からレコメンド候補を記録
                    let originalText = editState.originalTranscriptionText
                    let modifiedText = editState.transcriptionText
                    let changes = DictionaryRecommendationEngine.detectChanges(
                        original: originalText,
                        modified: modifiedText,
                        source: .userEdit
                    )
                    for change in changes {
                        RecommendationStore.record(
                            reading: change.reading,
                            display: change.display,
                            source: .userEdit
                        )
                    }

                    state.title = editState.title
                    // AI整理テキストがある場合はそちらを更新
                    if state.aiSummary != nil {
                        state.aiSummary?.summaryText = editState.transcriptionText
                    } else {
                        state.transcriptionText = editState.transcriptionText
                    }
                }
                return .send(._editSavedAndReload)

            case ._editSavedAndReload:
                // メモ詳細を再読み込み
                state.isLoading = true
                let memoID = state.memoID
                return .merge(
                    .run { send in
                        let result = await Result {
                            try await self.loadDetail(memoID: memoID)
                        }.mapError { EquatableError($0) }
                        await send(.memoLoaded(result))
                    },
                    .send(.checkDictionaryRecommendations)
                )

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
                    // AI整理完了時: STT原文とAI整理後テキストの差分からレコメンド候補を記録
                    let sttOriginal = state.transcriptionText
                    let aiText = state.aiSummary?.summaryText ?? ""
                    if !sttOriginal.isEmpty && !aiText.isEmpty {
                        let changes = DictionaryRecommendationEngine.detectChanges(
                            original: sttOriginal,
                            modified: aiText,
                            source: .aiCorrection
                        )
                        for change in changes {
                            RecommendationStore.record(
                                reading: change.reading,
                                display: change.display,
                                source: .aiCorrection
                            )
                        }
                    }

                    // AI処理完了時はメモ詳細を再読み込み + クォータ情報更新
                    let memoID = state.memoID
                    return .merge(
                        .run { send in
                            let result = await Result {
                                try await self.loadDetail(memoID: memoID)
                            }.mapError { EquatableError($0) }
                            await send(.memoLoaded(result))
                        },
                        .run { send in
                            let remaining = try await self.aiQuota.remainingCount()
                            let limit = self.aiQuota.monthlyLimit()
                            await send(._quotaInfoLoaded(remaining: remaining, limit: limit))
                        } catch: { _, _ in }
                    )
                }
                if case .failed(.networkError) = status {
                    // ネットワークエラー時はオフラインフォールバック案内のみ（自動リトライなし）
                    return .none
                }
                return .none

            // T09: AI要約の再生成（初回はオンボーディング表示）
            case .regenerateAISummary:
                // 初回オンボーディングチェック
                let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenAIOnboarding")
                if !hasSeenOnboarding {
                    state.showAIOnboarding = true
                    return .none
                }

                state.aiProcessingStatus = .queued
                let memoID = state.memoID
                return .run { send in
                    try await self.aiProcessingQueue.enqueueProcessing(memoID)
                } catch: { error, send in
                    await send(.aiProcessingStatusUpdated(
                        .failed(.processingFailed(error.localizedDescription))
                    ))
                }

            // T10: AI要約カードの展開/折りたたみ
            case .toggleSummaryExpanded:
                state.isSummaryExpanded.toggle()
                return .none

            // T09: AI分析を手動トリガー（初回はオンボーディング表示）
            // 手動実行専用: UIの「AI分析を実行する」ボタンからのみ呼ばれる。
            // AppReducer.recordingSaved で自動enqueue済みの場合は重複実行しない。
            case .triggerAIProcessing:
                // 既にAI処理中・キュー済み・完了済みなら何もしない（重複実行防止）
                switch state.aiProcessingStatus {
                case .queued, .processing:
                    return .none
                case .completed:
                    return .none
                case .idle, .failed:
                    break
                }

                // AI要約が既に存在する場合も何もしない（再生成はregenerateAISummaryで行う）
                if state.aiSummary != nil {
                    return .none
                }

                // 初回オンボーディングチェック
                let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenAIOnboarding")
                if !hasSeenOnboarding {
                    state.showAIOnboarding = true
                    return .none
                }

                state.aiProcessingStatus = .queued
                let memoID = state.memoID
                return .run { send in
                    try await self.aiProcessingQueue.enqueueProcessing(memoID)
                } catch: { error, send in
                    await send(.aiProcessingStatusUpdated(
                        .failed(.processingFailed(error.localizedDescription))
                    ))
                }

            // AIオンボーディング閉じ → フラグ保存 → AI処理実行
            case .aiOnboardingDismissed:
                state.showAIOnboarding = false
                UserDefaults.standard.set(true, forKey: "hasSeenAIOnboarding")
                // オンボーディング完了後にAI処理を実行
                return .send(.triggerAIProcessing)

            // T09: クォータ情報受信
            case let ._quotaInfoLoaded(remaining, limit):
                state.remainingQuota = remaining
                state.quotaLimit = limit
                return .none

            // MARK: - AIフィードバック

            case let .aiFeedbackTapped(isPositive):
                let feedback = AIFeedback(
                    memoID: state.memoID,
                    isPositive: isPositive,
                    writingStyle: WritingStyle.current.rawValue,
                    promptVersion: PromptTemplate.onDeviceSimple.version
                )
                state.aiFeedback = feedback
                AIFeedbackStore.saveFeedback(feedback)
                return .send(.aiFeedbackSaved)

            case .aiFeedbackSaved:
                return .none

            // MARK: - 辞書レコメンド

            case .checkDictionaryRecommendations:
                let recommendations = RecommendationStore.fetchRecommendations()
                state.dictionaryRecommendation = recommendations.first
                return .none

            case let .dictionaryRecommendationLoaded(recommendation):
                state.dictionaryRecommendation = recommendation
                return .none

            case let .acceptDictionaryRecommendation(recommendation):
                state.dictionaryRecommendation = nil
                let reading = recommendation.reading
                let display = recommendation.display
                let entryID = uuid()
                return .run { _ in
                    let entry = DictionaryEntry(id: entryID, reading: reading, display: display)
                    try await customDictionaryClient.addEntry(entry)
                    RecommendationStore.dismiss(reading: reading, display: display)
                } catch: { _, _ in
                    // 辞書登録失敗は静かに無視（UX原則1: 操作を止めない）
                }

            case let .dismissDictionaryRecommendation(recommendation):
                state.dictionaryRecommendation = nil
                RecommendationStore.dismiss(
                    reading: recommendation.reading,
                    display: recommendation.display
                )
                return .none

            case .tagTapped, .shareButtonTapped, .backButtonTapped:
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
