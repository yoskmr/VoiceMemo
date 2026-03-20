import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 録音完了画面
/// 保存後に達成感のあるフィードバックを表示し、メモ詳細への遷移を促す
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @State private var showCheckmark = false
    @State private var showPreview = false
    @State private var showCTA = false

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

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // チェックマーク（scaleアニメーション）
            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.vmSuccess)
                    .transition(.scale)
            }

            // 「保存しました」
            if showCheckmark {
                Text("保存しました")
                    .font(.vmTitle2)
                    .foregroundColor(.vmTextPrimary)
                    .transition(.opacity)
            }

            // 文字起こしプレビュー（最大4行）
            if showPreview {
                Text(transcriptionPreview)
                    .font(.vmBody())
                    .foregroundColor(.vmTextSecondary)
                    .lineLimit(4)
                    .padding(VMDesignTokens.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.vmSurfaceVariant)
                    .cornerRadius(VMDesignTokens.CornerRadius.small)
                    .padding(.horizontal, VMDesignTokens.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // AI処理インジケーター枠（Phase 3で実体化）
            if showPreview {
                HStack(spacing: VMDesignTokens.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.vmInfo)
                    Text("AI分析は準備中です")
                        .font(.vmCallout)
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
            if showCTA {
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
            if showCTA {
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
        .background(Color.vmBackground)
        .onAppear {
            // チェックマーク: 即座にspring表示
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showCheckmark = true
            }
            // プレビューテキスト: 0.3秒遅延
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                showPreview = true
            }
            // CTAボタン: 0.5秒遅延
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                showCTA = true
            }
        }
    }
}
