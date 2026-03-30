import Foundation

/// 感情カテゴリ（統一enum, 13段階）
/// 統合仕様書 v1.0 準拠（セクション3.2）: 全設計書でこのenumを使用すること
/// 日本語感情語彙拡張（8→13カテゴリ）— DES-006 セクション6 準拠
public enum EmotionCategory: String, Codable, CaseIterable, Sendable, Equatable {
    // 既存8カテゴリ
    case joy           = "joy"           // 喜び
    case calm          = "calm"          // 安心
    case anticipation  = "anticipation"  // 期待
    case sadness       = "sadness"       // 悲しみ
    case anxiety       = "anxiety"       // 不安
    case anger         = "anger"         // 怒り
    case surprise      = "surprise"      // 驚き
    case neutral       = "neutral"       // 中立

    // 新規5カテゴリ（DES-006）
    case gratitude     = "gratitude"     // 感謝
    case achievement   = "achievement"   // 達成感
    case nostalgia     = "nostalgia"     // 懐かしさ
    case ambivalence   = "ambivalence"   // もやもや
    case determination = "determination" // 決意

    /// 日本語表示名
    public var displayNameJA: String {
        switch self {
        case .joy: return "喜び"
        case .calm: return "安心"
        case .anticipation: return "期待"
        case .sadness: return "悲しみ"
        case .anxiety: return "不安"
        case .anger: return "怒り"
        case .surprise: return "驚き"
        case .neutral: return "中立"
        case .gratitude: return "感謝"
        case .achievement: return "達成感"
        case .nostalgia: return "懐かしさ"
        case .ambivalence: return "もやもや"
        case .determination: return "決意"
        }
    }

    /// 後方互換用の既存8カテゴリ配列
    /// マイグレーションやレガシーAPI連携で使用
    public static var legacyCategories: [EmotionCategory] {
        [.joy, .calm, .anticipation, .sadness, .anxiety, .anger, .surprise, .neutral]
    }
}
