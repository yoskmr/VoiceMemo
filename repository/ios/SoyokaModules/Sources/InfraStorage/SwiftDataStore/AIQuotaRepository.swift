import Domain
import Foundation
import SwiftData

/// SwiftData ベースの AIQuotaClient Live実装
/// JST基準で月次AI処理回数のカウントを管理する
/// Phase 3a: P3A-REQ-012 準拠
public final class AIQuotaRepository: @unchecked Sendable {

    private let modelContainer: ModelContainer
    private let jst: TimeZone
    private let limit: Int

    @MainActor
    private var context: ModelContext {
        modelContainer.mainContext
    }

    public init(
        modelContainer: ModelContainer,
        monthlyLimit: Int = 10
    ) {
        self.modelContainer = modelContainer
        self.jst = TimeZone(identifier: "Asia/Tokyo")!
        self.limit = monthlyLimit
    }

    // MARK: - Public API

    /// 今月のAI処理が可能か判定（月次上限以内）
    public func canProcess() async throws -> Bool {
        let usage = try await currentUsage()
        return usage < limit
    }

    /// AI処理実行を記録（カウント+1）
    public func recordUsage() async throws {
        try await MainActor.run {
            let record = AIQuotaRecordModel(processedAt: Date())
            context.insert(record)
            try context.save()
        }
    }

    /// 今月の使用回数を取得
    public func currentUsage() async throws -> Int {
        let currentMonthKey = currentYearMonthKey()
        return try await MainActor.run {
            let descriptor = FetchDescriptor<AIQuotaRecordModel>(
                predicate: #Predicate { $0.yearMonth == currentMonthKey }
            )
            return try context.fetchCount(descriptor)
        }
    }

    /// 月次上限
    public func monthlyLimit() -> Int {
        limit
    }

    /// 次回リセット日（翌月1日 JST 0:00）
    public func nextResetDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst

        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)

        // 翌月の1日 0:00 JST
        var nextMonthComponents = DateComponents()
        if components.month == 12 {
            nextMonthComponents.year = (components.year ?? 2026) + 1
            nextMonthComponents.month = 1
        } else {
            nextMonthComponents.year = components.year
            nextMonthComponents.month = (components.month ?? 1) + 1
        }
        nextMonthComponents.day = 1
        nextMonthComponents.hour = 0
        nextMonthComponents.minute = 0
        nextMonthComponents.second = 0

        return calendar.date(from: nextMonthComponents) ?? now
    }

    /// 残り回数を取得
    public func remainingCount() async throws -> Int {
        let usage = try await currentUsage()
        return max(0, limit - usage)
    }

    /// 今月の使用回数をリセット（デバッグ用）
    public func resetUsage() async throws {
        let currentMonthKey = currentYearMonthKey()
        try await MainActor.run {
            let descriptor = FetchDescriptor<AIQuotaRecordModel>(
                predicate: #Predicate { $0.yearMonth == currentMonthKey }
            )
            let records = try context.fetch(descriptor)
            for record in records {
                context.delete(record)
            }
            try context.save()
        }
    }

    // MARK: - Private Helpers

    /// 現在のJST年月キーを取得
    private func currentYearMonthKey() -> String {
        AIQuotaRecordModel.makeYearMonthKey(from: Date(), timeZone: jst)
    }
}

// MARK: - AIQuotaClient Live Value 生成

extension AIQuotaRepository {

    /// AIQuotaClient の Live インスタンスを生成
    public func toClient() -> AIQuotaClient {
        AIQuotaClient(
            canProcess: { [self] in try await self.canProcess() },
            recordUsage: { [self] in try await self.recordUsage() },
            currentUsage: { [self] in try await self.currentUsage() },
            monthlyLimit: { [self] in self.monthlyLimit() },
            nextResetDate: { [self] in self.nextResetDate() },
            remainingCount: { [self] in try await self.remainingCount() },
            resetUsage: { [self] in try await self.resetUsage() }
        )
    }
}
