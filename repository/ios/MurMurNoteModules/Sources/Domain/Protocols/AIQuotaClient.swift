import Dependencies
import Foundation

/// 月次AI処理回数のカウント管理を行うTCA Dependency
/// Phase 3a: 月15回の無料枠制限を管理する
/// P3A-REQ-012 準拠
public struct AIQuotaClient: Sendable {
    /// 今月のAI処理が可能か判定（月15回以内）
    public var canProcess: @Sendable () async throws -> Bool
    /// AI処理実行を記録（カウント+1）
    public var recordUsage: @Sendable () async throws -> Void
    /// 今月の使用回数を取得
    public var currentUsage: @Sendable () async throws -> Int
    /// 月次上限（デフォルト15）
    public var monthlyLimit: @Sendable () -> Int
    /// 次回リセット日（翌月1日 JST 0:00）
    public var nextResetDate: @Sendable () -> Date
    /// 残り回数を取得
    public var remainingCount: @Sendable () async throws -> Int

    public init(
        canProcess: @escaping @Sendable () async throws -> Bool,
        recordUsage: @escaping @Sendable () async throws -> Void,
        currentUsage: @escaping @Sendable () async throws -> Int,
        monthlyLimit: @escaping @Sendable () -> Int = { 15 },
        nextResetDate: @escaping @Sendable () -> Date,
        remainingCount: @escaping @Sendable () async throws -> Int
    ) {
        self.canProcess = canProcess
        self.recordUsage = recordUsage
        self.currentUsage = currentUsage
        self.monthlyLimit = monthlyLimit
        self.nextResetDate = nextResetDate
        self.remainingCount = remainingCount
    }
}

// MARK: - DependencyKey

extension AIQuotaClient: TestDependencyKey {
    public static let testValue = AIQuotaClient(
        canProcess: unimplemented("AIQuotaClient.canProcess", placeholder: true),
        recordUsage: unimplemented("AIQuotaClient.recordUsage"),
        currentUsage: unimplemented("AIQuotaClient.currentUsage", placeholder: 0),
        monthlyLimit: { 15 },
        nextResetDate: unimplemented("AIQuotaClient.nextResetDate", placeholder: Date()),
        remainingCount: unimplemented("AIQuotaClient.remainingCount", placeholder: 15)
    )
}

extension DependencyValues {
    public var aiQuota: AIQuotaClient {
        get { self[AIQuotaClient.self] }
        set { self[AIQuotaClient.self] = newValue }
    }
}
