import InfraSTT
import SharedUI
import SwiftUI

/// 初回起動時のウェルカム画面
/// WhisperKit モデルのダウンロードをバックグラウンドで行い、
/// 完了後に自動でメイン画面へ遷移する。
/// ダウンロード失敗時は Apple Speech にフォールバック（ユーザーには見せない）。
struct WelcomeView: View {
    /// ダウンロード進捗（0.0〜1.0）。WhisperKit API制約のため indeterminate 表示を併用
    @State private var downloadProgress: Double = 0
    /// モデル準備完了フラグ（完了 or フォールバック）
    @State private var isReady: Bool = false
    /// 準備中テキストのアニメーション用
    @State private var showProgress: Bool = false

    /// 初回セットアップ完了時のコールバック
    var onSetupComplete: () -> Void

    var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "bubble.left.fill")
                .font(.system(size: 56))
                .foregroundColor(.vmPrimary)

            Text("MurMurNote")
                .font(.vmTitle1)
                .foregroundColor(.vmTextPrimary)

            Text("声のままでいい。\nちゃんと残るから。")
                .font(.vmBody())
                .foregroundColor(.vmTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            // プログレス（準備中のみ表示）
            if showProgress && !isReady {
                VStack(spacing: VMDesignTokens.Spacing.sm) {
                    ProgressView()
                        .tint(.vmPrimary)
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
            startModelDownload()
        }
    }

    // MARK: - Private

    /// WhisperKit モデルのダウンロードを開始する
    /// 失敗時は Apple Speech フォールバック（静かに完了扱い）
    private func startModelDownload() {
        // 少し遅延してからプログレス表示（画面が落ち着いてから）
        withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
            showProgress = true
        }

        Task {
            let engine = WhisperKitEngine(modelName: "openai_whisper-base")

            // 既にダウンロード済みならすぐに完了
            if engine.isModelDownloaded() {
                await completeSetup()
                return
            }

            do {
                try await engine.downloadModel { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                // ダウンロード成功
                await completeSetup()
            } catch {
                // ダウンロード失敗 → Apple Speech フォールバック（静かに）
                #if DEBUG
                print("[Welcome] WhisperKit モデルダウンロード失敗（Apple Speechにフォールバック）: \(error)")
                #endif
                await completeSetup()
            }
        }
    }

    /// セットアップ完了処理
    @MainActor
    private func completeSetup() {
        withAnimation(.easeOut(duration: 0.4)) {
            isReady = true
        }
        // アニメーション完了後にコールバック
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onSetupComplete()
        }
    }
}
