import Foundation

/// AI整理の処理方法（プライバシー設定）
public enum AIProcessingMode: String, CaseIterable, Codable, Sendable, Equatable {
    /// おまかせ — デバイス優先、必要時のみクラウド（デフォルト）
    case auto
    /// デバイス内のみ — 一切クラウドに送信しない
    case deviceOnly

    public var displayName: String {
        switch self {
        case .auto: return "おまかせ"
        case .deviceOnly: return "デバイス内のみ"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "デバイス優先。より高度な機能ではクラウドを利用します"
        case .deviceOnly: return "すべてデバイス内で処理します。データは外部に送信されません"
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
