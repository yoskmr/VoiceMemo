import SharedUI
import SwiftUI

/// 録音経過時間表示ビュー
/// MM:SS形式でリアルタイム表示、録音中は最大時間を小さく薄く併記
/// 設計書 04-ui-design-system.md セクション4 準拠
struct TimerView: View {
    let elapsedTime: TimeInterval
    var isWarning: Bool = false
    var maxDuration: TimeInterval = 300
    var isRecording: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(formattedTime)
                .font(.vmTimer())
                .foregroundColor(isWarning ? .vmWarning : .vmTextPrimary)
                .monospacedDigit()

            if isRecording {
                Text("/ \(formattedMaxDuration)")
                    .font(.vmCaption1)
                    .foregroundColor(.vmTextTertiary)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("録音時間 \(formattedTime)")
    }

    /// 経過時間をMM:SS形式でフォーマット
    private var formattedTime: String {
        let totalSeconds = Int(elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 最大録音時間をM:SS形式でフォーマット
    private var formattedMaxDuration: String {
        let totalSeconds = Int(maxDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
