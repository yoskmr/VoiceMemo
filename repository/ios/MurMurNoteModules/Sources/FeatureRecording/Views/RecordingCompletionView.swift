import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// つぶやき完了画面
/// 温かく「受け止めた」ことを伝え、メモ詳細への遷移を促す
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @State private var showContent = false

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // 温かいアイコン（吹き出し＋チェック）
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 44))
                .foregroundColor(.vmPrimary.opacity(0.8))
                .scaleEffect(showContent ? 1 : 0.6)
                .opacity(showContent ? 1 : 0)

            // 温かいメッセージ
            Text("書きとめました")
                .font(.vmTitle3)
                .foregroundColor(.vmTextPrimary)
                .opacity(showContent ? 1 : 0)

            // 自動停止メッセージ
            if store.wasAutoStopped {
                Text("5分に達したので終了しました")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
                    .opacity(showContent ? 1 : 0)
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
            .opacity(showContent ? 1 : 0)
            .padding(.bottom, VMDesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vmBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }
}
