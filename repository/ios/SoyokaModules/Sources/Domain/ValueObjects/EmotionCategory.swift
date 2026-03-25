import Foundation

/// 感情カテゴリ（統一enum, 8段階）
/// 統合仕様書 v1.0 準拠（セクション3.2）: 全設計書でこのenumを使用すること
public enum EmotionCategory: String, Codable, CaseIterable, Sendable, Equatable {
    case joy           = "joy"           // 喜び
    case calm          = "calm"          // 安心
    case anticipation  = "anticipation"  // 期待
    case sadness       = "sadness"       // 悲しみ
    case anxiety       = "anxiety"       // 不安
    case anger         = "anger"         // 怒り
    case surprise      = "surprise"      // 驚き
    case neutral       = "neutral"       // 中立
}
