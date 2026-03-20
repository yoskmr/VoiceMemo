import SwiftUI

// MARK: - Design System Typography
// 設計書 04-ui-design-system.md セクション3 準拠
// 統合仕様書 v1.0 準拠: relativeTo: パラメータでDynamic Type対応

extension Font {
    // MARK: - 本文・日記テキスト用（丸ゴシック系で温かみ表現 NFR-012）
    public static func vmBody(_ size: CGFloat = 17) -> Font {
        .custom("HiraMaruProN-W4", size: size, relativeTo: .body)
    }

    public static func vmBodyBold(_ size: CGFloat = 17) -> Font {
        .custom("HiraMaruProN-W4", size: size, relativeTo: .body).bold()
    }

    // MARK: - UI要素用（SF Pro Rounded）
    public static func vmUI(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - タイマー表示用（SF Mono Rounded）
    public static func vmTimer(_ size: CGFloat = 48) -> Font {
        .system(size: size, weight: .light, design: .monospaced)
    }

    // MARK: - プリセット
    public static let vmLargeTitle = Font.vmUI(34, weight: .bold)
    public static let vmTitle1 = Font.vmUI(28, weight: .bold)
    public static let vmTitle2 = Font.vmUI(22, weight: .bold)
    public static let vmTitle3 = Font.vmUI(20, weight: .semibold)
    public static let vmHeadline = Font.vmUI(17, weight: .semibold)
    public static let vmCallout = Font.custom("HiraMaruProN-W4", size: 16, relativeTo: .callout)
    public static let vmSubheadline = Font.custom("HiraMaruProN-W4", size: 15, relativeTo: .subheadline)
    public static let vmFootnote = Font.custom("HiraMaruProN-W4", size: 13, relativeTo: .footnote)
    public static let vmCaption1 = Font.vmUI(12, weight: .regular)
    public static let vmCaption2 = Font.vmUI(11, weight: .regular)
}
