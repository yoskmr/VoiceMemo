import Foundation
import SwiftData

/// SwiftData @Model: AI処理キューのタスク永続化
/// Phase 3a: AI処理のキュー管理を SwiftData で永続化する
/// 設計書 DES-PHASE3A-001 セクション8.1 準拠
///
/// ステータス遷移:
/// queued → processing → completed
/// queued → processing → retrying → processing (リトライ)
/// queued → processing → retrying → failed (リトライ上限)
/// queued → cancelled / processing → cancelled
@Model
public final class AIProcessingTaskModel {
    @Attribute(.unique) public var id: UUID

    /// 対象メモのID
    public var memoId: UUID

    /// 処理ステータス: "queued" | "processing" | "completed" | "failed" | "cancelled" | "retrying"
    public var status: String

    /// 優先度: 0=high, 1=normal, 2=low
    public var priority: Int

    /// タスク作成日時
    public var createdAt: Date

    /// 処理開始日時
    public var startedAt: Date?

    /// 処理完了日時
    public var completedAt: Date?

    /// リトライ回数
    public var retryCount: Int

    /// 最大リトライ回数
    public var maxRetries: Int

    /// エラーメッセージ（失敗時）
    public var errorMessage: String?

    /// 使用したプロバイダ（LLMProviderType.rawValue）
    public var providerUsed: String?

    public init(
        id: UUID = UUID(),
        memoId: UUID,
        status: String = "queued",
        priority: Int = 1,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        retryCount: Int = 0,
        maxRetries: Int = 3,
        errorMessage: String? = nil,
        providerUsed: String? = nil
    ) {
        self.id = id
        self.memoId = memoId
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.retryCount = retryCount
        self.maxRetries = maxRetries
        self.errorMessage = errorMessage
        self.providerUsed = providerUsed
    }
}

// MARK: - ステータス定数

extension AIProcessingTaskModel {
    public enum Status {
        public static let queued = "queued"
        public static let processing = "processing"
        public static let completed = "completed"
        public static let failed = "failed"
        public static let cancelled = "cancelled"
        public static let retrying = "retrying"
    }
}
