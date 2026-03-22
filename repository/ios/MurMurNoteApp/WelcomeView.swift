import InfraSTT
import SharedUI
import SwiftUI

/// 初回起動時のウェルカム画面
/// WhisperKit モデルのダウンロードをバックグラウンドで行い、
/// 完了後に自動でメイン画面へ遷移する。
/// ダウンロード失敗時は Apple Speech にフォールバック（ユーザーには見せない）。
struct WelcomeView: View {
    /// ダウンロード進捗（0.0〜1.0）
    @State private var downloadProgress: Double = 0
    /// モデル準備完了フラグ
    @State private var isReady: Bool = false
    /// 準備中テキストのアニメーション用
    @State private var showProgress: Bool = false

    /// 初回セットアップ完了時のコールバック
    var onSetupComplete: () -> Void

    /// WhisperKit base モデルの概算サイズ（バイト）
    private static let estimatedModelSize: Double = 140_000_000

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
                .lineSpacing(VMDesignTokens.LineSpacing.body)

            Spacer()

            // プログレスバー（準備中のみ表示）
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
            startModelDownload()
        }
    }

    // MARK: - Private

    private func startModelDownload() {
        withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
            showProgress = true
        }

        Task {
            let engine = WhisperKitEngine(modelName: "openai_whisper-base")

            // 既にダウンロード済みならすぐに完了
            if engine.isModelDownloaded() {
                await MainActor.run { downloadProgress = 1.0 }
                await completeSetup()
                return
            }

            // 進捗監視タスク: ダウンロードフォルダのサイズを定期チェック
            let progressTask = Task {
                await monitorDownloadProgress()
            }

            do {
                try await engine.downloadModel { _ in }
                progressTask.cancel()
                await MainActor.run { downloadProgress = 1.0 }
                await completeSetup()
            } catch {
                progressTask.cancel()
                #if DEBUG
                print("[Welcome] WhisperKit モデルダウンロード失敗（Apple Speechにフォールバック）: \(error)")
                #endif
                await MainActor.run { downloadProgress = 1.0 }
                await completeSetup()
            }
        }
    }

    /// ダウンロードフォルダのサイズを監視して擬似プログレスを更新
    private func monitorDownloadProgress() async {
        let fm = FileManager.default
        // WhisperKitのデフォルトダウンロード先
        let possiblePaths = [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface"),
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Models")
        ].compactMap { $0 }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒ごと

            var totalSize: Double = 0
            for basePath in possiblePaths {
                totalSize += Self.directorySize(at: basePath)
            }

            let progress = min(totalSize / Self.estimatedModelSize, 0.95) // 95%まで
            await MainActor.run {
                withAnimation(.linear(duration: 0.3)) {
                    downloadProgress = progress
                }
            }
        }
    }

    /// ディレクトリの合計サイズを再帰的に計算
    private static func directorySize(at url: URL) -> Double {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var size: Double = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Double(fileSize)
            }
        }
        return size
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
