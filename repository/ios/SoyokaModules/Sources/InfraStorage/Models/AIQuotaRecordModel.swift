import Foundation
import SwiftData

/// SwiftData @Model: AI処理の月次カウント記録
/// Phase 3a: 月10回の無料枠を管理するための使用記録
/// 設計書 DES-PHASE3A-001 セクション8.2 準拠
@Model
public final class AIQuotaRecordModel {
    @Attribute(.unique) public var id: UUID
    /// 処理完了日時
    public var processedAt: Date
    /// JST基準の年月キー（"2026-03" 形式、月次集計用インデックス）
    public var yearMonth: String

    public init(
        id: UUID = UUID(),
        processedAt: Date = Date()
    ) {
        self.id = id
        self.processedAt = processedAt

        // JST基準で年月キーを生成
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let components = calendar.dateComponents([.year, .month], from: processedAt)
        self.yearMonth = String(format: "%04d-%02d", components.year!, components.month!)
    }

    /// 指定タイムゾーンで年月キーを生成するヘルパー
    static func makeYearMonthKey(from date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year!, components.month!)
    }
}
