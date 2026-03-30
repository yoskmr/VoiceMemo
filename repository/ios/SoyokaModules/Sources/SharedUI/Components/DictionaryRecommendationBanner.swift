import Domain
import SwiftUI

/// 辞書レコメンド提案バナー
/// UX原則1: 操作を止めない — 画面下部にさりげなく表示、スクロールの邪魔にならない
public struct DictionaryRecommendationBanner: View {
    let recommendation: DictionaryRecommendation
    let onAccept: () -> Void
    let onDismiss: () -> Void

    public init(
        recommendation: DictionaryRecommendation,
        onAccept: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.recommendation = recommendation
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: VMDesignTokens.Spacing.md) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundColor(.vmPrimary)

            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.xxs) {
                Text("よく使う言葉として登録？")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)

                Text("「\(recommendation.reading)」→「\(recommendation.display)」")
                    .font(.vmCallout)
                    .foregroundColor(.vmTextPrimary)
            }

            Spacer()

            Button("登録") { onAccept() }
                .font(.vmHeadline)
                .foregroundColor(.vmPrimary)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(.vmTextTertiary)
            }
        }
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.vertical, VMDesignTokens.Spacing.md)
        .background(Color.vmSurface)
        .cornerRadius(VMDesignTokens.CornerRadius.medium)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("辞書登録の提案: \(recommendation.reading)を\(recommendation.display)として登録")
    }
}
