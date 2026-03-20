import Foundation

/// タグの生成元
public enum TagSource: String, Codable, Sendable, Equatable {
    case ai       // AI自動付与
    case manual   // ユーザー手動
}
