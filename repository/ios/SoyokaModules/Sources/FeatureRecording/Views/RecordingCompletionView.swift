import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// つぶやき完了トースト
/// 録音画面下部にオーバーレイ表示される軽量フィードバックカード
/// UX原則: ユーザーの操作を止めない / すぐに反応を返す / iOSらしい軽さ
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stage = store.completionStage
        let animation: Animation? = reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)

        VStack(spacing: VMDesignTokens.Spacing.md) {
            // チェックマーク + メッセージ
            HStack(spacing: VMDesignTokens.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.vmPrimary)
                    .scaleEffect(stage >= .checkmark ? 1 : 0.4)
                    .opacity(stage >= .checkmark ? 1 : 0)
                    .animation(animation, value: stage)

                Text("書きとめました")
                    .font(.vmHeadline)
                    .foregroundColor(.vmTextPrimary)
                    .opacity(stage >= .checkmark ? 1 : 0)
                    .animation(animation, value: stage)
            }

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

            // 「きおくを見る」リンク
            if stage >= .cta {
                Button { store.send(.viewMemoTapped) } label: {
                    Text("きおくを見る")
                        .font(.vmCallout)
                        .foregroundColor(.vmPrimary)
                }
                .transition(.opacity)
                .animation(animation, value: stage)
            }
        }
        .padding(.vertical, VMDesignTokens.Spacing.lg)
        .padding(.horizontal, VMDesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: VMDesignTokens.CornerRadius.medium)
                .fill(Color.vmSurface)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
        .padding(.bottom, VMDesignTokens.Spacing.sm)
    }
}
