import InfraSTT
import SharedUI
import SwiftUI

/// 初回起動時のウェルカム画面
/// SpeechAnalyzer の言語パックを準備し、完了後にメイン画面へ遷移する。
struct WelcomeView: View {
    @State private var downloadProgress: Double = 0
    @State private var isReady: Bool = false
    @State private var showProgress: Bool = false

    var onSetupComplete: () -> Void

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "bubble.left.fill")
                .font(.system(size: 56))
                .foregroundColor(.vmPrimary)

            Text("そよか")
                .font(.vmTitle1)
                .foregroundColor(.vmTextPrimary)

            Text("Soyoka")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)

            Text("声のままでいい。\nちゃんと残るから。")
                .font(.vmBody())
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(VMDesignTokens.LineSpacing.body)

            Text("あなたの声を、整えて残します。")
                .font(.vmCaption1)
                .foregroundColor(.vmTextTertiary)
                .padding(.top, VMDesignTokens.Spacing.xs)

            Spacer()

            if showProgress && !isReady {
                VStack(spacing: VMDesignTokens.Spacing.sm) {
                    ProgressView(value: downloadProgress)
                        .tint(.vmPrimary)
                        .padding(.horizontal, VMDesignTokens.Spacing.xxxl)

                    Text("準備しています...")
                        .font(.vmCaption1)
                        .foregroundColor(.vmTextTertiary)
                }
                .transition(.opacity)
            }

            Spacer()
                .frame(height: VMDesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vmBackground.ignoresSafeArea())
        .onAppear {
            prepareSTTEngine()
        }
    }

    // MARK: - Private

    private func prepareSTTEngine() {
        withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
            showProgress = true
        }

        Task {
            if #available(iOS 26.0, *) {
                let engine = SpeechAnalyzerEngine()

                // 言語パックが利用可能か確認
                if await engine.isAvailable() {
                    await MainActor.run { downloadProgress = 1.0 }
                    await completeSetup()
                    return
                }

                // 言語パックをダウンロード
                do {
                    await MainActor.run { downloadProgress = 0.3 }
                    try await engine.downloadLanguagePack(locale: Locale(identifier: "ja-JP"))
                    await MainActor.run { downloadProgress = 1.0 }
                    await completeSetup()
                } catch {
                    #if DEBUG
                    print("[Welcome] 言語パックDL失敗（Apple Speechにフォールバック）: \(error)")
                    #endif
                    await MainActor.run { downloadProgress = 1.0 }
                    await completeSetup()
                }
            } else {
                // iOS 26未満: すぐに完了
                await MainActor.run { downloadProgress = 1.0 }
                await completeSetup()
            }
        }
    }

    @MainActor
    private func completeSetup() {
        withAnimation(.easeOut(duration: 0.4)) {
            isReady = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onSetupComplete()
        }
    }
}
