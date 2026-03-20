import SwiftUI

// MARK: - Design System Colors
// 設計書 04-ui-design-system.md セクション2 準拠
// NFR-012: 暖色系パレット（HSB色相20-40）

extension Color {
    // MARK: Primary（暖色系ジャーナル風）
    public static let vmPrimary = Color(hue: 20.0 / 360.0, saturation: 0.54, brightness: 0.91)
    public static let vmPrimaryLight = Color(hue: 25.0 / 360.0, saturation: 0.38, brightness: 0.95)
    public static let vmPrimaryDark = Color(hue: 20.0 / 360.0, saturation: 0.65, brightness: 0.77)

    // MARK: Secondary
    public static let vmSecondary = Color(hue: 30.0 / 360.0, saturation: 0.45, brightness: 0.83)
    public static let vmSecondaryLight = Color(hue: 30.0 / 360.0, saturation: 0.28, brightness: 0.91)
    public static let vmSecondaryDark = Color(hue: 30.0 / 360.0, saturation: 0.53, brightness: 0.65)

    // MARK: Accent
    public static let vmAccent = Color(hue: 40.0 / 360.0, saturation: 0.66, brightness: 0.88)
    public static let vmAccentLight = Color(hue: 40.0 / 360.0, saturation: 0.46, brightness: 0.94)
    public static let vmAccentDark = Color(hue: 40.0 / 360.0, saturation: 0.75, brightness: 0.72)

    // MARK: Semantic
    public static let vmSuccess = Color(red: 93.0 / 255.0, green: 170.0 / 255.0, blue: 104.0 / 255.0)
    public static let vmWarning = Color(red: 224.0 / 255.0, green: 160.0 / 255.0, blue: 48.0 / 255.0)
    public static let vmError = Color(red: 208.0 / 255.0, green: 96.0 / 255.0, blue: 80.0 / 255.0)
    public static let vmInfo = Color(red: 96.0 / 255.0, green: 152.0 / 255.0, blue: 192.0 / 255.0)

    // MARK: Neutral（Asset Catalogが無い場合のフォールバック）
    public static let vmBackground = Color(red: 253.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0)
    public static let vmSurface = Color.white
    public static let vmSurfaceVariant = Color(red: 245.0 / 255.0, green: 237.0 / 255.0, blue: 228.0 / 255.0)
    public static let vmTextPrimary = Color(red: 44.0 / 255.0, green: 36.0 / 255.0, blue: 32.0 / 255.0)
    public static let vmTextSecondary = Color(red: 107.0 / 255.0, green: 93.0 / 255.0, blue: 82.0 / 255.0)
    public static let vmTextTertiary = Color(red: 160.0 / 255.0, green: 148.0 / 255.0, blue: 135.0 / 255.0)
    public static let vmDivider = Color(red: 232.0 / 255.0, green: 221.0 / 255.0, blue: 210.0 / 255.0)
}
