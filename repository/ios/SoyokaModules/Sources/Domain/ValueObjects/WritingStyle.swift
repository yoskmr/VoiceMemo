import Foundation

/// AI整理の文体（ユーザー選択）
public enum WritingStyle: String, CaseIterable, Codable, Sendable, Equatable {
    /// やわらかく — フィラーだけ取って、話した感じを残す（デフォルト）
    case soft
    /// きちんと — ですます調に丁寧に整える
    case formal
    /// ひとりごと — SNS的な短文、体言止め
    case casual
    /// ふりかえり — 未来の自分が語りかけるような手紙風（近日公開）
    case reflection
    /// エッセイ — 日常を短い随筆に（近日公開）
    case essay

    public var displayName: String {
        switch self {
        case .soft: return "やわらかく"
        case .formal: return "きちんと"
        case .casual: return "ひとりごと"
        case .reflection: return "ふりかえり"
        case .essay: return "エッセイ"
        }
    }

    public var description: String {
        switch self {
        case .soft: return "フィラーだけ取って、話した感じを残す"
        case .formal: return "ですます調に丁寧に整える"
        case .casual: return "SNS的な短文、体言止め。気軽に"
        case .reflection: return "未来の自分が語りかけるような手紙風"
        case .essay: return "日常を短い随筆に。情景描写を加える"
        }
    }

    /// 現在利用可能かどうか（false = 近日公開）
    public var isAvailable: Bool {
        switch self {
        case .soft, .formal, .casual: return true
        case .reflection, .essay: return false
        }
    }

    /// ユーザー設定から取得（UserDefaults）
    public static var current: WritingStyle {
        guard let raw = UserDefaults.standard.string(forKey: "writingStyle"),
              let style = WritingStyle(rawValue: raw) else {
            return .soft
        }
        return style
    }

    /// ユーザー設定に保存
    public static func setCurrent(_ style: WritingStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: "writingStyle")
    }
}
