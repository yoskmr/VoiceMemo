import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design System Colors
// 設計書 04-ui-design-system.md セクション2 準拠
// NFR-012: 暖色系パレット（HSB色相20-40）

extension Color {
    // MARK: - Adaptive Color Helper

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: Primary（暖色系ジャーナル風）
    // ダーク: 彩度を少し下げ明度を上げて暗い背景で映える色味に
    public static let vmPrimary = adaptive(
        light: UIColor(hue: 20.0 / 360.0, saturation: 0.54, brightness: 0.91, alpha: 1),
        dark: UIColor(hue: 20.0 / 360.0, saturation: 0.48, brightness: 0.95, alpha: 1)
    )
    public static let vmPrimaryLight = adaptive(
        light: UIColor(hue: 25.0 / 360.0, saturation: 0.38, brightness: 0.95, alpha: 1),
        dark: UIColor(hue: 25.0 / 360.0, saturation: 0.45, brightness: 0.30, alpha: 1)
    )
    public static let vmPrimaryDark = adaptive(
        light: UIColor(hue: 20.0 / 360.0, saturation: 0.65, brightness: 0.77, alpha: 1),
        dark: UIColor(hue: 20.0 / 360.0, saturation: 0.55, brightness: 0.85, alpha: 1)
    )

    // MARK: Secondary
    public static let vmSecondary = adaptive(
        light: UIColor(hue: 30.0 / 360.0, saturation: 0.45, brightness: 0.83, alpha: 1),
        dark: UIColor(hue: 30.0 / 360.0, saturation: 0.40, brightness: 0.88, alpha: 1)
    )
    public static let vmSecondaryLight = adaptive(
        light: UIColor(hue: 30.0 / 360.0, saturation: 0.28, brightness: 0.91, alpha: 1),
        dark: UIColor(hue: 30.0 / 360.0, saturation: 0.35, brightness: 0.32, alpha: 1)
    )
    public static let vmSecondaryDark = adaptive(
        light: UIColor(hue: 30.0 / 360.0, saturation: 0.53, brightness: 0.65, alpha: 1),
        dark: UIColor(hue: 30.0 / 360.0, saturation: 0.45, brightness: 0.78, alpha: 1)
    )

    // MARK: Accent
    public static let vmAccent = adaptive(
        light: UIColor(hue: 40.0 / 360.0, saturation: 0.66, brightness: 0.88, alpha: 1),
        dark: UIColor(hue: 40.0 / 360.0, saturation: 0.58, brightness: 0.92, alpha: 1)
    )
    public static let vmAccentLight = adaptive(
        light: UIColor(hue: 40.0 / 360.0, saturation: 0.46, brightness: 0.94, alpha: 1),
        dark: UIColor(hue: 40.0 / 360.0, saturation: 0.50, brightness: 0.30, alpha: 1)
    )
    public static let vmAccentDark = adaptive(
        light: UIColor(hue: 40.0 / 360.0, saturation: 0.75, brightness: 0.72, alpha: 1),
        dark: UIColor(hue: 40.0 / 360.0, saturation: 0.65, brightness: 0.82, alpha: 1)
    )

    // MARK: Semantic
    public static let vmSuccess = adaptive(
        light: UIColor(red: 93.0 / 255.0, green: 170.0 / 255.0, blue: 104.0 / 255.0, alpha: 1),
        dark: UIColor(red: 110.0 / 255.0, green: 190.0 / 255.0, blue: 120.0 / 255.0, alpha: 1)
    )
    public static let vmWarning = adaptive(
        light: UIColor(red: 224.0 / 255.0, green: 160.0 / 255.0, blue: 48.0 / 255.0, alpha: 1),
        dark: UIColor(red: 240.0 / 255.0, green: 180.0 / 255.0, blue: 70.0 / 255.0, alpha: 1)
    )
    public static let vmError = adaptive(
        light: UIColor(red: 208.0 / 255.0, green: 96.0 / 255.0, blue: 80.0 / 255.0, alpha: 1),
        dark: UIColor(red: 225.0 / 255.0, green: 115.0 / 255.0, blue: 100.0 / 255.0, alpha: 1)
    )
    public static let vmInfo = adaptive(
        light: UIColor(red: 96.0 / 255.0, green: 152.0 / 255.0, blue: 192.0 / 255.0, alpha: 1),
        dark: UIColor(red: 120.0 / 255.0, green: 175.0 / 255.0, blue: 210.0 / 255.0, alpha: 1)
    )

    // MARK: Neutral（ライト/ダーク適応）
    public static let vmBackground = adaptive(
        light: UIColor(red: 253.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0, alpha: 1),
        dark: UIColor(red: 28.0 / 255.0, green: 24.0 / 255.0, blue: 22.0 / 255.0, alpha: 1)
    )
    public static let vmSurface = adaptive(
        light: .white,
        dark: UIColor(red: 42.0 / 255.0, green: 36.0 / 255.0, blue: 32.0 / 255.0, alpha: 1)
    )
    public static let vmSurfaceVariant = adaptive(
        light: UIColor(red: 245.0 / 255.0, green: 237.0 / 255.0, blue: 228.0 / 255.0, alpha: 1),
        dark: UIColor(red: 52.0 / 255.0, green: 44.0 / 255.0, blue: 38.0 / 255.0, alpha: 1)
    )
    public static let vmTextPrimary = adaptive(
        light: UIColor(red: 44.0 / 255.0, green: 36.0 / 255.0, blue: 32.0 / 255.0, alpha: 1),
        dark: UIColor(red: 240.0 / 255.0, green: 232.0 / 255.0, blue: 224.0 / 255.0, alpha: 1)
    )
    public static let vmTextSecondary = adaptive(
        light: UIColor(red: 107.0 / 255.0, green: 93.0 / 255.0, blue: 82.0 / 255.0, alpha: 1),
        dark: UIColor(red: 180.0 / 255.0, green: 168.0 / 255.0, blue: 156.0 / 255.0, alpha: 1)
    )
    public static let vmTextTertiary = adaptive(
        light: UIColor(red: 160.0 / 255.0, green: 148.0 / 255.0, blue: 135.0 / 255.0, alpha: 1),
        dark: UIColor(red: 120.0 / 255.0, green: 110.0 / 255.0, blue: 100.0 / 255.0, alpha: 1)
    )
    public static let vmDivider = adaptive(
        light: UIColor(red: 232.0 / 255.0, green: 221.0 / 255.0, blue: 210.0 / 255.0, alpha: 1),
        dark: UIColor(red: 60.0 / 255.0, green: 52.0 / 255.0, blue: 44.0 / 255.0, alpha: 1)
    )
}
