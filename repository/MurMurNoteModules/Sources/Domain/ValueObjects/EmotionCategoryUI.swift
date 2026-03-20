import Foundation

/// EmotionCategory の表示用プロパティ
/// 設計書 04-ui-design-system.md セクション4.3 準拠
extension EmotionCategory {
    /// 日本語ラベル
    public var label: String {
        switch self {
        case .joy: return "喜び"
        case .calm: return "安心"
        case .anticipation: return "期待"
        case .sadness: return "悲しみ"
        case .anxiety: return "不安"
        case .anger: return "怒り"
        case .surprise: return "驚き"
        case .neutral: return "中立"
        }
    }

    /// SF Symbols アイコン名
    public var iconName: String {
        switch self {
        case .joy: return "sun.max.fill"
        case .calm: return "leaf.fill"
        case .anticipation: return "sparkles"
        case .sadness: return "cloud.rain.fill"
        case .anxiety: return "wind"
        case .anger: return "flame.fill"
        case .surprise: return "bolt.fill"
        case .neutral: return "circle.fill"
        }
    }
}
