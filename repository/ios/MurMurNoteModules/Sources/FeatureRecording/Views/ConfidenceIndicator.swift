import SharedUI
import SwiftUI

/// 文字起こし信頼度インジケーター
struct ConfidenceIndicator: View {
    let level: ConfidenceLevel

    var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.xs) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(indicatorLabel)
                .font(.vmCaption1)
                .foregroundColor(.vmTextSecondary)
        }
        .padding(.horizontal, VMDesignTokens.Spacing.sm)
        .padding(.vertical, VMDesignTokens.Spacing.xs)
        .background(Color.vmSurfaceVariant.opacity(0.8))
        .clipShape(Capsule())
    }

    private var indicatorColor: Color {
        switch level {
        case .high:
            return .vmSuccess
        case .medium:
            return .vmWarning
        case .low:
            return .vmError
        }
    }

    private var indicatorLabel: String {
        switch level {
        case .high:
            return "高精度"
        case .medium:
            return "中精度"
        case .low:
            return "低精度"
        }
    }
}
