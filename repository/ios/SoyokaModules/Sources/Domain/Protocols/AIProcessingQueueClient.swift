import Dependencies
import Foundation

/// AI処理のエラー種別
/// Phase 3 UXレビュー: エラー種別を詳細化し、UIでの分岐表示に対応
public enum AIProcessingError: Equatable, Sendable {
    /// 月間クォータ超過（残り回数、リセット日）
    case quotaExceeded(remaining: Int, resetDate: Date)
    /// ネットワークエラー（詳細メッセージ）
    case networkError(String)
    /// 処理失敗（詳細メッセージ）
    case processingFailed(String)
}

/// AI処理のステータス
/// Step 6: AI処理バックグラウンド基盤
/// Phase 3 UXレビュー: processing に進捗情報、completed にオンデバイス判定を追加
public enum AIProcessingStatus: Equatable, Sendable {
    case idle
    case queued
    /// 処理中（progress: 0.0〜1.0、description: 処理段階の説明）
    case processing(progress: Double, description: String)
    /// 処理完了（isOnDevice: オンデバイス処理かどうか）
    case completed(isOnDevice: Bool)
    /// 処理失敗（詳細エラー）
    case failed(AIProcessingError)
}

/// AI処理キューの TCA Dependency クライアント
/// バックグラウンドでのAI処理（要約・感情分析等）をキュー管理する
public struct AIProcessingQueueClient: Sendable {
    /// メモIDを指定してAI処理をキューに追加
    public var enqueueProcessing: @Sendable (UUID) async throws -> Void
    /// メモIDの処理ステータスを監視するストリーム
    public var observeStatus: @Sendable (UUID) -> AsyncStream<AIProcessingStatus>
    /// メモIDの処理をキャンセル
    public var cancelProcessing: @Sendable (UUID) async throws -> Void

    public init(
        enqueueProcessing: @escaping @Sendable (UUID) async throws -> Void,
        observeStatus: @escaping @Sendable (UUID) -> AsyncStream<AIProcessingStatus>,
        cancelProcessing: @escaping @Sendable (UUID) async throws -> Void
    ) {
        self.enqueueProcessing = enqueueProcessing
        self.observeStatus = observeStatus
        self.cancelProcessing = cancelProcessing
    }
}

// MARK: - DependencyKey

extension AIProcessingQueueClient: TestDependencyKey {
    public static let testValue = AIProcessingQueueClient(
        enqueueProcessing: unimplemented("AIProcessingQueueClient.enqueueProcessing"),
        observeStatus: unimplemented("AIProcessingQueueClient.observeStatus", placeholder: AsyncStream { $0.finish() }),
        cancelProcessing: unimplemented("AIProcessingQueueClient.cancelProcessing")
    )
}

extension DependencyValues {
    public var aiProcessingQueue: AIProcessingQueueClient {
        get { self[AIProcessingQueueClient.self] }
        set { self[AIProcessingQueueClient.self] = newValue }
    }
}
