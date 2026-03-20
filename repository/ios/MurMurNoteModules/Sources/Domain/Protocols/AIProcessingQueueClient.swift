import Dependencies
import Foundation

/// AI処理のステータス
/// Step 6: AI処理バックグラウンド基盤
public enum AIProcessingStatus: Equatable, Sendable {
    case idle
    case queued
    case processing
    case completed
    case failed(String)
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
