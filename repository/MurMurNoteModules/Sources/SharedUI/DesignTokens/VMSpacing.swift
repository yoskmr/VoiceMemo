import SwiftUI

// MARK: - Design System Tokens
// 設計書 04-ui-design-system.md セクション12 準拠

/// デザイントークン統合定義
public enum VMDesignTokens {

    // MARK: - Spacing

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    // MARK: - Corner Radius（NFR-012: 角丸12pt以上）

    public enum CornerRadius {
        /// NFR-012 最小値
        public static let small: CGFloat = 12
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 20
        /// 完全な円
        public static let pill: CGFloat = 40
    }

    // MARK: - Animation Duration

    public enum Duration {
        /// タブ切替
        public static let fast: Double = 0.2
        /// 標準遷移
        public static let normal: Double = 0.35
        /// モーダル
        public static let slow: Double = 0.4
    }

    // MARK: - Touch Target（Apple HIG準拠）

    public enum TouchTarget {
        public static let minimum: CGFloat = 44
    }
}
