import SwiftUI

/// タグチップコンポーネント
/// 設計書 04-ui-design-system.md セクション4.4 準拠
public struct TagChip: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text("#\(text)")
            .font(.vmCaption2)
            .foregroundColor(.vmSecondaryDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.vmAccentLight.opacity(0.5))
            .cornerRadius(VMDesignTokens.CornerRadius.small)
            .accessibilityLabel("タグ: \(text)")
    }
}
