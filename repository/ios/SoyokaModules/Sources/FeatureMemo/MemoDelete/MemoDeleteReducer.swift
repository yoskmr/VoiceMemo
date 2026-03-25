import ComposableArchitecture
import Domain
import Foundation

/// メモ削除のTCA Reducer
/// TASK-0017: メモ削除 + 確認ダイアログ
/// SwiftData + 音声ファイル + FTS5インデックスの3つを一貫して削除
/// 設計書 01-system-architecture.md セクション5.1 ER図 準拠
@Reducer
public struct MemoDeleteReducer {

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public var pendingDeleteID: UUID?
        public var showDeleteConfirmation: Bool
        public var isDeleting: Bool
        public var deleteError: String?

        public init(
            pendingDeleteID: UUID? = nil,
            showDeleteConfirmation: Bool = false,
            isDeleting: Bool = false,
            deleteError: String? = nil
        ) {
            self.pendingDeleteID = pendingDeleteID
            self.showDeleteConfirmation = showDeleteConfirmation
            self.isDeleting = isDeleting
            self.deleteError = deleteError
        }
    }

    // MARK: - Action

    public enum Action: Equatable, Sendable {
        case deleteRequested(id: UUID)
        case deleteConfirmed(id: UUID)
        case deleteCancelled
        case deleteCompleted(DeleteResult)
    }

    /// 削除結果のEquatable準拠ラッパー
    public enum DeleteResult: Equatable, Sendable {
        case success(UUID)
        case failure(String)
    }

    // MARK: - Dependencies

    @Dependency(\.voiceMemoRepository) var voiceMemoRepository
    @Dependency(\.audioFileStore) var audioFileStore
    @Dependency(\.fts5IndexManager) var fts5IndexManager

    // MARK: - Reducer Body

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .deleteRequested(id):
                state.pendingDeleteID = id
                state.showDeleteConfirmation = true
                return .none

            case let .deleteConfirmed(id):
                state.showDeleteConfirmation = false
                state.isDeleting = true
                return .run { [fts5IndexManager] send in
                    do {
                        // 1. メモの音声ファイルパスを取得
                        let audioPath = try await voiceMemoRepository.getAudioFilePath(id)

                        // 2. SwiftData削除（cascade: Transcription, AISummary, EmotionAnalysis）
                        try await voiceMemoRepository.delete(id)

                        // 3. 音声ファイルの物理削除（ベストエフォート）
                        do {
                            try await audioFileStore.deleteAudioFile(audioPath)
                        } catch {
                            // ファイル不存在等は警告のみ（続行）
                        }

                        // 4. FTS5インデックスから削除（ベストエフォート）
                        do {
                            try fts5IndexManager.removeIndex(id.uuidString)
                        } catch {
                            // FTS5エラーは警告のみ（続行）
                        }

                        await send(.deleteCompleted(.success(id)))
                    } catch {
                        await send(.deleteCompleted(.failure(error.localizedDescription)))
                    }
                }

            case .deleteCancelled:
                state.pendingDeleteID = nil
                state.showDeleteConfirmation = false
                return .none

            case let .deleteCompleted(.success(_)):
                state.isDeleting = false
                state.pendingDeleteID = nil
                return .none

            case let .deleteCompleted(.failure(errorMessage)):
                state.isDeleting = false
                state.deleteError = errorMessage
                return .none
            }
        }
    }
}
