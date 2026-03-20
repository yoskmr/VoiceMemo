import ComposableArchitecture
import Domain
import SharedUI
import SwiftUI

/// 音声プレイヤーView
/// TASK-0014: 音声再生コントロール + シークバー
/// 設計書 04-ui-design-system.md セクション6.3 音声プレイヤー部分
public struct AudioPlayerView: View {
    @Bindable var store: StoreOf<AudioPlayerReducer>

    public init(store: StoreOf<AudioPlayerReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: VMDesignTokens.Spacing.sm) {
            HStack(spacing: VMDesignTokens.Spacing.md) {
                // 再生/停止ボタン
                Button {
                    switch store.playerStatus {
                    case .playing:
                        store.send(.pauseTapped)
                    default:
                        store.send(.playTapped)
                    }
                } label: {
                    Image(systemName: store.playerStatus == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.vmPrimary)
                        .frame(
                            width: VMDesignTokens.TouchTarget.minimum,
                            height: VMDesignTokens.TouchTarget.minimum
                        )
                }
                .accessibilityLabel(store.playerStatus == .playing ? "一時停止" : "再生")
                .accessibilityHint("ダブルタップで\(store.playerStatus == .playing ? "一時停止" : "再生開始")します")

                // シークバー
                Slider(
                    value: Binding(
                        get: { store.progress },
                        set: { store.send(.sliderDragChanged($0)) }
                    ),
                    in: 0...1,
                    onEditingChanged: { isDragging in
                        if isDragging {
                            store.send(.sliderDragStarted)
                        } else {
                            store.send(.sliderDragEnded)
                        }
                    }
                )
                .tint(.vmPrimary)
                .accessibilityLabel("再生位置")
                .accessibilityValue("\(formattedTime(store.currentTime)) / \(formattedTime(store.duration))")

                // 時間表示
                Text("\(formattedTime(store.currentTime)) / \(formattedTime(store.duration))")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, VMDesignTokens.Spacing.md)
            .padding(.vertical, VMDesignTokens.Spacing.sm)
            .background(Color.vmSurfaceVariant)
            .cornerRadius(VMDesignTokens.CornerRadius.small)
        }
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// ハイライト付きテキスト表示
/// TASK-0014: 再生位置とテキストのハイライト同期
public struct HighlightedTranscriptionView: View {
    public let segments: [AudioPlayerReducer.TimestampedSegment]
    public let highlightedIndex: Int?
    public let onSegmentTapped: (TimeInterval) -> Void

    public init(
        segments: [AudioPlayerReducer.TimestampedSegment],
        highlightedIndex: Int?,
        onSegmentTapped: @escaping (TimeInterval) -> Void
    ) {
        self.segments = segments
        self.highlightedIndex = highlightedIndex
        self.onSegmentTapped = onSegmentTapped
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(segments) { segment in
                Text(segment.text)
                    .font(.vmBody())
                    .foregroundColor(.vmTextPrimary)
                    .padding(.vertical, VMDesignTokens.Spacing.xxs)
                    .background(
                        segment.id == highlightedIndex
                            ? Color.vmPrimaryLight.opacity(0.3)
                            : Color.clear
                    )
                    .cornerRadius(4)
                    .onTapGesture {
                        onSegmentTapped(segment.startTime)
                    }
                    .animation(.easeInOut(duration: VMDesignTokens.Duration.fast), value: highlightedIndex)
            }
        }
        .textSelection(.enabled)
    }
}
