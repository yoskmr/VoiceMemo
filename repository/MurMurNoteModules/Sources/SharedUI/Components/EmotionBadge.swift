import Domain
import SwiftUI

/// 感情バッジコンポーネント
/// 設計書 04-ui-design-system.md セクション4.3 準拠
public struct EmotionBadge: View {
    public let emotion: EmotionCategory

    public init(emotion: EmotionCategory) {
        self.emotion = emotion
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: emotion.iconName)
                .font(.system(size: 12))
            Text(emotion.label)
                .font(.vmCaption1)
        }
        .foregroundColor(emotionColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(emotionColor.opacity(0.12))
        .cornerRadius(VMDesignTokens.CornerRadius.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("感情: \(emotion.label)")
    }

    private var emotionColor: Color {
        switch emotion {
        case .joy: return Color(red: 224.0 / 255.0, green: 168.0 / 255.0, blue: 76.0 / 255.0)
        case .calm: return Color(red: 93.0 / 255.0, green: 170.0 / 255.0, blue: 104.0 / 255.0)
        case .anticipation: return Color(red: 96.0 / 255.0, green: 152.0 / 255.0, blue: 192.0 / 255.0)
        case .sadness: return Color(red: 120.0 / 255.0, green: 144.0 / 255.0, blue: 180.0 / 255.0)
        case .anxiety: return Color(red: 160.0 / 255.0, green: 148.0 / 255.0, blue: 135.0 / 255.0)
        case .anger: return Color(red: 208.0 / 255.0, green: 96.0 / 255.0, blue: 80.0 / 255.0)
        case .surprise: return Color(red: 180.0 / 255.0, green: 120.0 / 255.0, blue: 200.0 / 255.0)
        case .neutral: return Color(red: 160.0 / 255.0, green: 148.0 / 255.0, blue: 135.0 / 255.0)
        }
    }
}
