import ComposableArchitecture
import SharedUI
import SwiftUI

/// 初回AI処理時に表示するオンボーディングシート
/// T12: Phase 3a - 初回AI処理オンボーディング
/// 設計書 UX-PHASE3A-001 セクション5 準拠
public struct AIOnboardingView: View {
    let store: StoreOf<AIProcessingReducer>

    public init(store: StoreOf<AIProcessingReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // ヘッダーアイコン
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.vmPrimary)
                .accessibilityHidden(true)

            // タイトル
            Text("AI分析機能について")
                .font(.vmTitle2)
                .foregroundColor(.vmTextPrimary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, VMDesignTokens.Spacing.xxl)

            // 説明セクション
            VStack(alignment: .leading, spacing: VMDesignTokens.Spacing.lg) {
                featureRow(
                    icon: "doc.text.magnifyingglass",
                    text: "録音内容をAIが自動で要約・タグ付けします"
                )

                featureRow(
                    icon: "lock.shield",
                    text: "この処理はお使いのデバイス上で行われます。テキストは外部に送信されません"
                )

                featureRow(
                    icon: "gift",
                    text: "毎月15回まで無料でご利用いただけます"
                )
            }
            .padding(.horizontal, VMDesignTokens.Spacing.xxl)

            Divider()
                .padding(.horizontal, VMDesignTokens.Spacing.xxl)

            Spacer()

            // CTAボタン
            Button {
                store.send(.onboardingDismissed)
            } label: {
                Text("はじめる")
                    .font(.vmHeadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VMDesignTokens.Spacing.md)
            }
            .background(Color.vmPrimaryDark)
            .cornerRadius(VMDesignTokens.CornerRadius.medium)
            .padding(.horizontal, VMDesignTokens.Spacing.xxl)
            .padding(.bottom, VMDesignTokens.Spacing.xxl)
        }
        .background(Color.vmBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI分析機能の説明")
    }

    // MARK: - Private Helpers

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: VMDesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.vmPrimary)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            Text(text)
                .font(.vmBody())
                .foregroundColor(.vmTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
