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
        .foregroundColor(emotion.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(emotion.color.opacity(0.12))
        .cornerRadius(VMDesignTokens.CornerRadius.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("感情: \(emotion.label)")
    }
}
