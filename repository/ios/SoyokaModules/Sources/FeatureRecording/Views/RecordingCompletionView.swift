import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// つぶやき完了画面
/// 温かく「受け止めた」ことを伝え、メモ詳細への遷移を促す
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stage = store.completionStage
        let animation: Animation? = reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8)

        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // 温かいアイコン（吹き出し + チェック）
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 44))
                .foregroundColor(.vmPrimary.opacity(0.8))
                .scaleEffect(stage >= .checkmark ? 1 : 0.6)
                .opacity(stage >= .checkmark ? 1 : 0)
                .animation(animation, value: stage)

            // 温かいメッセージ
            Text("書きとめました")
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)
                .opacity(stage >= .preview ? 1 : 0)
                .animation(animation, value: stage)

            // AI処理状態表示
            if stage >= .preview {
                if store.aiProcessingCompleted {
                    HStack(spacing: VMDesignTokens.Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.vmCaption1)
                            .foregroundColor(.vmPrimary)
                        Text("整えました")
                            .font(.vmCaption1)
                            .foregroundColor(.vmTextSecondary)
                    }
                    .transition(.opacity)
                    .animation(animation, value: store.aiProcessingCompleted)
                } else {
                    HStack(spacing: VMDesignTokens.Spacing.xs) {
                        if reduceMotion {
                            Circle()
                                .fill(Color.vmPrimary.opacity(0.6))
                                .frame(width: 8, height: 8)
                        } else {
                            PulsingDotView()
                        }
                        Text("ことばを整えています…")
                            .font(.vmCaption1)
                            .foregroundColor(.vmTextTertiary)
                    }
                    .transition(.opacity)
                    .animation(animation, value: store.aiProcessingCompleted)
                }
            }

            // 自動停止メッセージ
            if store.wasAutoStopped {
                Text("5分に達したので終了しました")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
                    .opacity(stage >= .preview ? 1 : 0)
                    .animation(animation, value: stage)
            }

            Spacer()

            // ボタン
            VStack(spacing: VMDesignTokens.Spacing.md) {
                Button { store.send(.viewMemoTapped) } label: {
                    Text("メモを見る")
                        .font(.vmHeadline)
                        .foregroundColor(.vmPrimary)
                }

                Button { store.send(.dismissCompletion) } label: {
                    Text("あとで")
                        .font(.vmCallout)
                        .foregroundColor(.vmTextTertiary)
                }
            }
            .opacity(stage >= .cta ? 1 : 0)
            .animation(animation, value: stage)
            .padding(.bottom, VMDesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vmBackground.ignoresSafeArea())
    }
}
