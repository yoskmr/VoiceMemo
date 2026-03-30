import SwiftUI

/// アニメーションプリセット
/// 設計書 04-ui-design-system.md セクション5 準拠
public enum VMAnimations {
    /// ナビゲーションプッシュ遷移
    public static let navigationPush: Animation = .easeInOut(duration: 0.3)
    /// モーダル表示
    public static let modalPresent: Animation = .spring(response: 0.4, dampingFraction: 0.85)
    /// タブ切替
    public static let tabSwitch: Animation = .easeInOut(duration: 0.2)
    /// フェードイン・アウト
    public static let fade: Animation = .easeInOut(duration: 0.25)
    /// スケール（ボタンタップ等）
    public static let scale: Animation = .spring(response: 0.3, dampingFraction: 0.7)

    /// アニメーション時間定数
    public enum Duration {
        public static let fast: Double = 0.15
        public static let normal: Double = 0.3
        public static let slow: Double = 0.5
    }
}
