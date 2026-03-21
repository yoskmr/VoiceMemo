import SharedUI
import SwiftUI

/// 録音経過時間表示ビュー
/// MM:SS形式でリアルタイム表示
/// 設計書 04-ui-design-system.md セクション4 準拠
struct TimerView: View {
    let elapsedTime: TimeInterval
    var isWarning: Bool = false

    var body: some View {
        Text(formattedTime)
            .font(.vmTimer())
            .foregroundColor(isWarning ? .vmWarning : .vmTextPrimary)
            .monospacedDigit()
            .accessibilityLabel("録音時間 \(formattedTime)")
    }

    /// 経過時間をMM:SS形式でフォーマット
    private var formattedTime: String {
        let totalSeconds = Int(elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
