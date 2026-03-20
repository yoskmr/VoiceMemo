import Foundation

/// テーマの種別
public enum ThemeType: String, Codable, Sendable, Equatable {
    case system
    case light
    case dark
    case journal  // 感性的ジャーナルテーマ (NFR-012)
}
