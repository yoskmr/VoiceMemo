import Foundation

/// AI整理の処理方法（プライバシー設定）
public enum AIProcessingMode: String, CaseIterable, Codable, Sendable, Equatable {
    /// おまかせ — デバイス優先で処理（デフォルト）
    case auto
    /// デバイス内のみ — すべてデバイス内で処理
    case deviceOnly

    public var displayName: String {
        switch self {
        case .auto: return "おまかせ"
        case .deviceOnly: return "デバイス内のみ"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "デバイス優先で処理します"
        case .deviceOnly: return "すべてデバイス内で処理します"
        }
    }

    public static var current: AIProcessingMode {
        guard let raw = UserDefaults.standard.string(forKey: "aiProcessingMode"),
              let mode = AIProcessingMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }

    public static func setCurrent(_ mode: AIProcessingMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "aiProcessingMode")
    }
}
