import Domain
import SwiftUI

/// EmotionCategory の色定義（一元管理）
/// 設計書 04-ui-design-system.md セクション4.3 準拠
/// Domain層はSwiftUIに依存できないため、SharedUI層で色を定義する
/// P1-4: 新規5カテゴリの色定義追加（DES-006 セクション6 準拠）
extension EmotionCategory {
    /// 感情カテゴリに対応するテーマカラー
    public var color: Color {
        switch self {
        case .joy: return Color(red: 224.0 / 255.0, green: 168.0 / 255.0, blue: 76.0 / 255.0)
        case .calm: return Color(red: 93.0 / 255.0, green: 170.0 / 255.0, blue: 104.0 / 255.0)
        case .anticipation: return Color(red: 96.0 / 255.0, green: 152.0 / 255.0, blue: 192.0 / 255.0)
        case .sadness: return Color(red: 120.0 / 255.0, green: 144.0 / 255.0, blue: 180.0 / 255.0)
        case .anxiety: return Color(red: 160.0 / 255.0, green: 148.0 / 255.0, blue: 135.0 / 255.0)
        case .anger: return Color(red: 208.0 / 255.0, green: 96.0 / 255.0, blue: 80.0 / 255.0)
        case .surprise: return Color(red: 180.0 / 255.0, green: 120.0 / 255.0, blue: 200.0 / 255.0)
        case .neutral: return Color(red: 160.0 / 255.0, green: 148.0 / 255.0, blue: 135.0 / 255.0)
        // P1-4 新規5カテゴリ
        case .gratitude: return Color(red: 165.0 / 255.0, green: 214.0 / 255.0, blue: 167.0 / 255.0)       // #A5D6A7
        case .achievement: return Color(red: 255.0 / 255.0, green: 224.0 / 255.0, blue: 130.0 / 255.0)      // #FFE082
        case .nostalgia: return Color(red: 188.0 / 255.0, green: 170.0 / 255.0, blue: 164.0 / 255.0)        // #BCAAA4
        case .ambivalence: return Color(red: 176.0 / 255.0, green: 190.0 / 255.0, blue: 197.0 / 255.0)      // #B0BEC5
        case .determination: return Color(red: 121.0 / 255.0, green: 134.0 / 255.0, blue: 203.0 / 255.0)    // #7986CB
        }
    }
}
