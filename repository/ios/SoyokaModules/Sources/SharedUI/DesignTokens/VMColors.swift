import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design System Colors
// 設計書 04-ui-design-system.md セクション2 準拠
// NFR-012: 暖色系パレット（HSB色相20-40）
// ライト/ダーク両対応: 暖色系の世界観を維持しつつダークモードに適応

#if canImport(UIKit)

// MARK: - Adaptive Color Helper

private func vmAdaptive(light: UIColor, dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

// MARK: - Primary（暖色系ジャーナル風）

extension Color {
    // ダーク: 彩度を少し下げ明度を上げて暗い背景で映える色味に
    public static let vmPrimary: Color = vmAdaptive(
        light: UIColor(hue: 0.0556, saturation: 0.54, brightness: 0.91, alpha: 1),
        dark: UIColor(hue: 0.0556, saturation: 0.48, brightness: 0.95, alpha: 1)
    )
    public static let vmPrimaryLight: Color = vmAdaptive(
        light: UIColor(hue: 0.0694, saturation: 0.38, brightness: 0.95, alpha: 1),
        dark: UIColor(hue: 0.0694, saturation: 0.45, brightness: 0.30, alpha: 1)
    )
    public static let vmPrimaryDark: Color = vmAdaptive(
        light: UIColor(hue: 0.0556, saturation: 0.65, brightness: 0.77, alpha: 1),
        dark: UIColor(hue: 0.0556, saturation: 0.55, brightness: 0.85, alpha: 1)
    )
}

// MARK: - Secondary

extension Color {
    public static let vmSecondary: Color = vmAdaptive(
        light: UIColor(hue: 0.0833, saturation: 0.45, brightness: 0.83, alpha: 1),
        dark: UIColor(hue: 0.0833, saturation: 0.40, brightness: 0.88, alpha: 1)
    )
    public static let vmSecondaryLight: Color = vmAdaptive(
        light: UIColor(hue: 0.0833, saturation: 0.28, brightness: 0.91, alpha: 1),
        dark: UIColor(hue: 0.0833, saturation: 0.35, brightness: 0.32, alpha: 1)
    )
    public static let vmSecondaryDark: Color = vmAdaptive(
        light: UIColor(hue: 0.0833, saturation: 0.53, brightness: 0.65, alpha: 1),
        dark: UIColor(hue: 0.0833, saturation: 0.45, brightness: 0.78, alpha: 1)
    )
}

// MARK: - Accent

extension Color {
    public static let vmAccent: Color = vmAdaptive(
        light: UIColor(hue: 0.1111, saturation: 0.66, brightness: 0.88, alpha: 1),
        dark: UIColor(hue: 0.1111, saturation: 0.58, brightness: 0.92, alpha: 1)
    )
    public static let vmAccentLight: Color = vmAdaptive(
        light: UIColor(hue: 0.1111, saturation: 0.46, brightness: 0.94, alpha: 1),
        dark: UIColor(hue: 0.1111, saturation: 0.50, brightness: 0.30, alpha: 1)
    )
    public static let vmAccentDark: Color = vmAdaptive(
        light: UIColor(hue: 0.1111, saturation: 0.75, brightness: 0.72, alpha: 1),
        dark: UIColor(hue: 0.1111, saturation: 0.65, brightness: 0.82, alpha: 1)
    )
}

// MARK: - Semantic

extension Color {
    public static let vmSuccess: Color = vmAdaptive(
        light: UIColor(red: 0.365, green: 0.667, blue: 0.408, alpha: 1),
        dark: UIColor(red: 0.431, green: 0.745, blue: 0.471, alpha: 1)
    )
    public static let vmWarning: Color = vmAdaptive(
        light: UIColor(red: 0.878, green: 0.627, blue: 0.188, alpha: 1),
        dark: UIColor(red: 0.941, green: 0.706, blue: 0.275, alpha: 1)
    )
    public static let vmError: Color = vmAdaptive(
        light: UIColor(red: 0.816, green: 0.376, blue: 0.314, alpha: 1),
        dark: UIColor(red: 0.882, green: 0.451, blue: 0.392, alpha: 1)
    )
    public static let vmInfo: Color = vmAdaptive(
        light: UIColor(red: 0.376, green: 0.596, blue: 0.753, alpha: 1),
        dark: UIColor(red: 0.471, green: 0.686, blue: 0.824, alpha: 1)
    )
}

// MARK: - Neutral

extension Color {
    public static let vmBackground: Color = vmAdaptive(
        light: UIColor(red: 0.992, green: 0.973, blue: 0.953, alpha: 1),
        dark: UIColor(red: 0.110, green: 0.094, blue: 0.086, alpha: 1)
    )
    public static let vmSurface: Color = vmAdaptive(
        light: .white,
        dark: UIColor(red: 0.165, green: 0.141, blue: 0.125, alpha: 1)
    )
    public static let vmSurfaceVariant: Color = vmAdaptive(
        light: UIColor(red: 0.961, green: 0.929, blue: 0.894, alpha: 1),
        dark: UIColor(red: 0.204, green: 0.173, blue: 0.149, alpha: 1)
    )
    public static let vmTextPrimary: Color = vmAdaptive(
        light: UIColor(red: 0.173, green: 0.141, blue: 0.125, alpha: 1),
        dark: UIColor(red: 0.941, green: 0.910, blue: 0.878, alpha: 1)
    )
    public static let vmTextSecondary: Color = vmAdaptive(
        light: UIColor(red: 0.420, green: 0.365, blue: 0.322, alpha: 1),
        dark: UIColor(red: 0.706, green: 0.659, blue: 0.612, alpha: 1)
    )
    public static let vmTextTertiary: Color = vmAdaptive(
        light: UIColor(red: 0.627, green: 0.580, blue: 0.529, alpha: 1),
        dark: UIColor(red: 0.471, green: 0.431, blue: 0.392, alpha: 1)
    )
    public static let vmDivider: Color = vmAdaptive(
        light: UIColor(red: 0.910, green: 0.867, blue: 0.824, alpha: 1),
        dark: UIColor(red: 0.235, green: 0.204, blue: 0.173, alpha: 1)
    )
}

#else

// MARK: - Fallback (non-UIKit platforms)

extension Color {
    public static let vmPrimary = Color(hue: 0.0556, saturation: 0.54, brightness: 0.91)
    public static let vmPrimaryLight = Color(hue: 0.0694, saturation: 0.38, brightness: 0.95)
    public static let vmPrimaryDark = Color(hue: 0.0556, saturation: 0.65, brightness: 0.77)

    public static let vmSecondary = Color(hue: 0.0833, saturation: 0.45, brightness: 0.83)
    public static let vmSecondaryLight = Color(hue: 0.0833, saturation: 0.28, brightness: 0.91)
    public static let vmSecondaryDark = Color(hue: 0.0833, saturation: 0.53, brightness: 0.65)

    public static let vmAccent = Color(hue: 0.1111, saturation: 0.66, brightness: 0.88)
    public static let vmAccentLight = Color(hue: 0.1111, saturation: 0.46, brightness: 0.94)
    public static let vmAccentDark = Color(hue: 0.1111, saturation: 0.75, brightness: 0.72)

    public static let vmSuccess = Color(red: 0.365, green: 0.667, blue: 0.408)
    public static let vmWarning = Color(red: 0.878, green: 0.627, blue: 0.188)
    public static let vmError = Color(red: 0.816, green: 0.376, blue: 0.314)
    public static let vmInfo = Color(red: 0.376, green: 0.596, blue: 0.753)

    public static let vmBackground = Color(red: 0.992, green: 0.973, blue: 0.953)
    public static let vmSurface = Color.white
    public static let vmSurfaceVariant = Color(red: 0.961, green: 0.929, blue: 0.894)
    public static let vmTextPrimary = Color(red: 0.173, green: 0.141, blue: 0.125)
    public static let vmTextSecondary = Color(red: 0.420, green: 0.365, blue: 0.322)
    public static let vmTextTertiary = Color(red: 0.627, green: 0.580, blue: 0.529)
    public static let vmDivider = Color(red: 0.910, green: 0.867, blue: 0.824)
}

#endif
