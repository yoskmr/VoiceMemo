import SwiftUI

/// 録音ボタンコンポーネント
/// 3状態（idle: 赤円、recording: 赤正方形、paused: 角丸正方形 cornerRadius:16）
/// 設計書 04-ui-design-system.md セクション4.1 準拠
public struct RecordButton: View {

    /// 録音状態
    public enum Status: Equatable, Sendable {
        case idle
        case recording
        case paused
    }

    let status: Status
    let action: () -> Void

    public init(status: Status, action: @escaping () -> Void) {
        self.status = status
        self.action = action
    }

    @ScaledMetric(relativeTo: .title) private var outerSize: CGFloat = 80
    @ScaledMetric(relativeTo: .title) private var innerCircleSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var stopSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var pausedSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var micIconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title) private var playIconSize: CGFloat = 16

    public var body: some View {
        Button(action: action) {
            ZStack {
                // 外枠の円（背景）
                Circle()
                    .fill(outerFillColor)
                    .frame(width: outerSize, height: outerSize)

                // 内部形状（状態に応じて変化）
                innerShape
            }
        }
        .animation(.easeInOut(duration: VMDesignTokens.Duration.fast), value: status)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Inner Shape

    @ViewBuilder
    private var innerShape: some View {
        switch status {
        case .idle:
            // 赤い円 + マイクアイコン（録音開始ボタン）
            Circle()
                .fill(Color.vmPrimary)
                .frame(width: innerCircleSize, height: innerCircleSize)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: micIconSize, weight: .medium))
                        .foregroundColor(.white)
                }

        case .recording:
            // 赤い正方形（録音中 → 停止ボタン）
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.vmError)
                .frame(width: stopSize, height: stopSize)

        case .paused:
            // 角丸正方形 cornerRadius:16（一時停止中 → 再開ボタン）
            RoundedRectangle(cornerRadius: VMDesignTokens.CornerRadius.medium)
                .fill(Color.vmWarning)
                .frame(width: pausedSize, height: pausedSize)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: playIconSize, weight: .medium))
                        .foregroundColor(.white)
                }
        }
    }

    // MARK: - Styling

    private var outerFillColor: Color {
        switch status {
        case .idle:
            return Color.vmPrimary.opacity(0.15)
        case .recording:
            return Color.vmError.opacity(0.15)
        case .paused:
            return Color.vmWarning.opacity(0.15)
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch status {
        case .idle:
            return "録音開始"
        case .recording:
            return "録音停止"
        case .paused:
            return "録音再開"
        }
    }

    private var accessibilityHint: String {
        switch status {
        case .idle:
            return "タップして録音を開始します"
        case .recording:
            return "タップして録音を停止します"
        case .paused:
            return "タップして録音を再開します"
        }
    }
}
