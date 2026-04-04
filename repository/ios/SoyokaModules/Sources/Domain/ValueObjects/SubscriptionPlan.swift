import Foundation

/// サブスクリプションプランの識別子
/// 統合仕様書 INT-SPEC-001 準拠
public enum SubscriptionPlan: String, Codable, Sendable, Equatable {
    /// 無料プラン（月10回まで）
    case free = "free"
    /// Proプラン（無制限 + 高精度仕上げ利用可能）
    case pro = "pro"
}
