import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// つぶやき完了画面
/// 保存後にフィードバックを表示し、メモ詳細への遷移を促す
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    @State private var showContent = false

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // チェックマーク
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.vmSuccess)
                .scaleEffect(showContent ? 1 : 0.5)
                .opacity(showContent ? 1 : 0)

            // 「保存しました」
            Text("保存しました")
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }
        }
    }
}
