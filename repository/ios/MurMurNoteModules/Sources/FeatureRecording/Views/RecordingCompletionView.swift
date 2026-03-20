import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 録音完了画面
/// 保存後に達成感のあるフィードバックを表示し、メモ詳細への遷移を促す
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 保存されたメモから文字起こしプレビューを取得（最大100文字）
    private var transcriptionPreview: String {
        guard case let .saved(memo) = store.recordingStatus else {
            return ""
        }
        let fullText = memo.transcription?.fullText ?? ""
        if fullText.isEmpty {
            return "（文字起こしなし）"
        }
        if fullText.count > 100 {
            return String(fullText.prefix(100)) + "..."
        }
        return fullText
    }

    /// reduceMotion対応: アニメーションを条件付きで適用
    private var stageAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.3)
    }

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // チェックマーク（scaleアニメーション）
            if store.completionStage != .initial {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.vmSuccess)
                    .transition(reduceMotion ? .opacity : .scale)
            }

            // 「保存しました」
            if store.completionStage != .initial {
                Text("保存しました")
                    .font(.vmTitle2)
                    .foregroundColor(.vmTextPrimary)
                    .transition(.opacity)
            }

            // 文字起こしプレビュー（最大4行）
            if store.completionStage == .preview || store.completionStage == .cta {
                Text(transcriptionPreview)
                    .font(.vmBody())
                    .foregroundColor(.vmTextSecondary)
                    .lineLimit(4)
                    .padding(VMDesignTokens.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.vmSurfaceVariant)
                    .cornerRadius(VMDesignTokens.CornerRadius.small)
                    .padding(.horizontal, VMDesignTokens.Spacing.lg)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            // AI処理インジケーター（Phase 3 UXレビュー: テキスト改善）
            if store.completionStage == .preview || store.completionStage == .cta {
                VStack(spacing: VMDesignTokens.Spacing.xs) {
                    HStack(spacing: VMDesignTokens.Spacing.sm) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.vmInfo)
                        Text("AI分析をバックグラウンドで実行中")
                            .font(.vmCallout)
                            .foregroundColor(.vmTextSecondary)
                    }
                    Text("要約・タグ付け・感情分析を自動で行います")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
                .padding(VMDesignTokens.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.vmInfo.opacity(0.1))
                .cornerRadius(VMDesignTokens.CornerRadius.small)
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .transition(.opacity)
            }

            Spacer()

            // CTAボタン「メモを見る」
            if store.completionStage == .cta {
                Button {
                    store.send(.viewMemoTapped)
                } label: {
                    Text("メモを見る")
                        .font(.vmHeadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.vmPrimaryDark)
                        .cornerRadius(VMDesignTokens.CornerRadius.pill)
                }
                .padding(.horizontal, VMDesignTokens.Spacing.lg)
                .transition(.opacity)
            }

            // 「あとで」テキストボタン
            if store.completionStage == .cta {
                Button {
                    store.send(.dismissCompletion)
                } label: {
                    Text("あとで")
                        .font(.vmCallout)
                        .foregroundColor(.vmTextTertiary)
                }
                .padding(.bottom, VMDesignTokens.Spacing.xxxl)
                .transition(.opacity)
            }
        }
        .animation(stageAnimation, value: store.completionStage)
        .background(Color.vmBackground)
    }
}
