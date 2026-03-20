import ComposableArchitecture
import SharedUI
import SwiftUI

/// 録音画面（ホーム画面）メインビュー
/// 設計書 01-system-architecture.md セクション2.3 準拠
/// fullScreenCoverとして表示される録音オーバーレイ
public struct RecordingView: View {
    @Bindable var store: StoreOf<RecordingFeature>

    public init(store: StoreOf<RecordingFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if case .saved = store.recordingStatus {
                RecordingCompletionView(store: store)
            } else {
                recordingContent
            }
        }
    }

    @ViewBuilder
    private var recordingContent: some View {
        VStack(spacing: VMDesignTokens.Spacing.xl) {
            Spacer()

            // 録音経過時間
            TimerView(elapsedTime: store.elapsedTime)

            // 波形アニメーション
            WaveformView(
                audioLevel: store.audioLevel,
                isRecording: store.recordingStatus == .recording
            )
            .padding(.horizontal, VMDesignTokens.Spacing.xl)

            // リアルタイム文字起こし
            RealtimeTranscriptionView(
                text: store.partialTranscription,
                confidenceLevel: store.confidenceLevel
            )
            .padding(.horizontal, VMDesignTokens.Spacing.lg)

            Spacer()

            // エラーメッセージ
            if let errorMessage = store.errorMessage {
                errorBanner(errorMessage)
            }

            // 録音コントロール
            recordingControls
                .padding(.bottom, VMDesignTokens.Spacing.xxxl)
        }
        .background(Color.vmBackground)
    }

    // MARK: - Recording Controls

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: VMDesignTokens.Spacing.xxxl) {
            // メイン録音ボタン（タップで録音開始/停止をトグル）
            RecordButton(status: recordButtonStatus) {
                switch store.recordingStatus {
                case .idle:
                    store.send(.recordButtonTapped)
                case .recording, .paused:
                    store.send(.stopButtonTapped)
                case .saving, .saved:
                    break
                }
            }
            .disabled(store.recordingStatus == .saving)

            // 一時停止/再開ボタン（録音中・一時停止中のみ表示、右側）
            if store.recordingStatus == .recording || store.recordingStatus == .paused {
                Button {
                    if store.recordingStatus == .paused {
                        store.send(.resumeButtonTapped)
                    } else {
                        store.send(.pauseButtonTapped)
                    }
                } label: {
                    Image(systemName: store.recordingStatus == .paused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.vmSecondary)
                }
                .accessibilityLabel(store.recordingStatus == .paused ? "再開" : "一時停止")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: VMDesignTokens.Duration.fast), value: store.recordingStatus)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: VMDesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.vmError)
            Text(message)
                .font(.vmCallout)
                .foregroundColor(.vmTextPrimary)
        }
        .padding(VMDesignTokens.Spacing.md)
        .background(Color.vmError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VMDesignTokens.CornerRadius.small))
        .padding(.horizontal, VMDesignTokens.Spacing.lg)
    }

    // MARK: - Helpers

    /// RecordingFeature.State.RecordingStatus → RecordButton.Status 変換
    private var recordButtonStatus: RecordButton.Status {
        switch store.recordingStatus {
        case .idle: return .idle
        case .recording: return .recording
        case .paused: return .paused
        case .saving: return .idle
        case .saved: return .idle
        }
    }
}
