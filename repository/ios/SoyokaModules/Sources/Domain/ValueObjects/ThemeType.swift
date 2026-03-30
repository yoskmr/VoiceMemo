import Foundation

/// テーマの種別（外観モード）
public enum ThemeType: String, CaseIterable, Codable, Sendable, Equatable {
    /// システムに従う（デフォルト）
    case system
    /// 常にライト
    case light
    /// 常にダーク
    case dark
    case journal  // 感性的ジャーナルテーマ (NFR-012)

    public var displayName: String {
        switch self {
        case .system: return "システムに従う"
        case .light: return "ライト"
        case .dark: return "ダーク"
        case .journal: return "ジャーナル"
        }
    }

    /// UserDefaults から現在の外観モードを取得
    public static var current: ThemeType {
        guard let raw = UserDefaults.standard.string(forKey: "themeType"),
              let theme = ThemeType(rawValue: raw) else {
            return .system
        }
        return theme
    }

    /// UserDefaults に現在の外観モードを保存
    public static func setCurrent(_ theme: ThemeType) {
        UserDefaults.standard.set(theme.rawValue, forKey: "themeType")
    }
}
