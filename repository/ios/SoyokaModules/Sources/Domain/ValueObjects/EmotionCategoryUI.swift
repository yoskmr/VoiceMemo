import Foundation

/// EmotionCategory の表示用プロパティ
/// 設計書 04-ui-design-system.md セクション4.3 準拠
extension EmotionCategory {
    /// 日本語ラベル
    public var label: String { displayNameJA }

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
        case .gratitude: return "heart.fill"
        case .achievement: return "trophy.fill"
        case .nostalgia: return "photo.fill"
        case .ambivalence: return "cloud.fog.fill"
        case .determination: return "flag.fill"
        }
    }
}
