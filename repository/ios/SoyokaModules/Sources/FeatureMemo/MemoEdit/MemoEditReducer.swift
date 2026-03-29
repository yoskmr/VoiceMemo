import ComposableArchitecture
import Domain
import Foundation
import SharedUtil

/// メモテキスト編集のTCA Reducer
/// TASK-0013: 文字起こしテキスト編集・自動保存（デバウンス2秒）
/// 設計書 01-system-architecture.md セクション2.2 準拠
@Reducer
public struct MemoEditReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public let memoID: UUID
        public var title: String
        public var transcriptionText: String

        /// 変更検出用の元テキスト
        public var originalTitle: String
        public var originalTranscriptionText: String

        /// UI状態
        public var isSaving: Bool
        public var hasUnsavedChanges: Bool
        public var showDiscardAlert: Bool
        public var saveSuccessMessage: String?
        public var errorMessage: String?

        public var isModified: Bool {
            title != originalTitle || transcriptionText != originalTranscriptionText
        }

        public init(
            memoID: UUID,
            title: String = "",
            transcriptionText: String = "",
            originalTitle: String = "",
            originalTranscriptionText: String = "",
            isSaving: Bool = false,
            hasUnsavedChanges: Bool = false,
            showDiscardAlert: Bool = false,
            saveSuccessMessage: String? = nil,
            errorMessage: String? = nil
        ) {
            self.memoID = memoID
            self.title = title
            self.transcriptionText = transcriptionText
            self.originalTitle = originalTitle
            self.originalTranscriptionText = originalTranscriptionText
            self.isSaving = isSaving
            self.hasUnsavedChanges = hasUnsavedChanges
            self.showDiscardAlert = showDiscardAlert
            self.saveSuccessMessage = saveSuccessMessage
            self.errorMessage = errorMessage
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case onAppear(title: String, transcriptionText: String)
        case onDisappear
        case titleChanged(String)
        case transcriptionTextChanged(String)
        case saveButtonTapped
        case autoSaveTriggered
        case saveCompleted(TaskResultEquatable)
        case backButtonTapped
        case discardConfirmed
        case discardCancelled
        case dismissSaveSuccess
    }

    /// Result<Void, Error> のEquatable準拠ラッパー
    public enum TaskResultEquatable: Equatable, Sendable {
        case success
        case failure(String)
    }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.fts5IndexManager) var fts5IndexManager
    @Dependency(\.continuousClock) var clock
    @Dependency(\.analyticsClient) var analyticsClient

    // MARK: - Cancellation IDs

    enum AutoSaveID { case debounce }
    enum SuccessMessageID { case dismiss }

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(title, transcriptionText):
                state.title = title
                state.transcriptionText = transcriptionText
                state.originalTitle = title
                state.originalTranscriptionText = transcriptionText
                return .none

            case .onDisappear:
                // AutoSave/SuccessMessageのタイマーを自身で責任を持ってキャンセル（#14: 親への漏洩防止）
                return .merge(
                    .cancel(id: AutoSaveID.debounce),
                    .cancel(id: SuccessMessageID.dismiss)
                )

            case let .titleChanged(newTitle):
                state.title = newTitle
                state.hasUnsavedChanges = state.isModified
                return .none

            case let .transcriptionTextChanged(newText):
                state.transcriptionText = newText
                state.hasUnsavedChanges = state.isModified
                return .none

            case .saveButtonTapped, .autoSaveTriggered:
                guard state.isModified, !state.isSaving else { return .none }
                state.isSaving = true
                let memoID = state.memoID
                let title = state.title
                let text = state.transcriptionText
                return .run { [fts5IndexManager] send in
                    do {
                        try await voiceMemoRepository.updateMemoText(memoID, title, text)
                        try fts5IndexManager.upsertIndex(
                            memoID.uuidString, title, text, "", ""
                        )
                        await send(.saveCompleted(.success))
                    } catch {
                        await send(.saveCompleted(.failure(error.localizedDescription)))
                    }
                }

            case .saveCompleted(.success):
                state.isSaving = false
                state.originalTitle = state.title
                state.originalTranscriptionText = state.transcriptionText
                state.hasUnsavedChanges = false
                state.saveSuccessMessage = "書きとめました"
                analyticsClient.send("memo.edited")
                return .run { send in
                    try await clock.sleep(for: .seconds(2))
                    await send(.dismissSaveSuccess)
                }
                .cancellable(id: SuccessMessageID.dismiss, cancelInFlight: true)

            case let .saveCompleted(.failure(errorMessage)):
                state.isSaving = false
                state.errorMessage = errorMessage
                return .none

            case .backButtonTapped:
                if state.hasUnsavedChanges {
                    state.showDiscardAlert = true
                    return .none
                }
                return .none

            case .discardConfirmed:
                state.showDiscardAlert = false
                state.hasUnsavedChanges = false
                return .cancel(id: AutoSaveID.debounce)

            case .discardCancelled:
                state.showDiscardAlert = false
                return .none

            case .dismissSaveSuccess:
                state.saveSuccessMessage = nil
                return .none
            }
        }
    }
}
