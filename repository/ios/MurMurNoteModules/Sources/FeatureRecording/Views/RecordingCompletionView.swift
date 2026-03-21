import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 録音完了画面
/// 保存後のシンプルなフィードバックを表示し、メモ詳細への遷移を促す
struct RecordingCompletionView: View {
    let store: StoreOf<RecordingFeature>

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.vmSuccess)

            Text("保存しました")
                .font(.vmHeadline)
                .foregroundColor(.vmTextPrimary)

            if store.wasAutoStopped {
                Text("5分に達したので終了しました")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
            }

            Spacer()

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
            .padding(.bottom, VMDesignTokens.Spacing.xxxl)
        }
        .background(Color.vmBackground)
        .transition(.opacity)
    }
}
