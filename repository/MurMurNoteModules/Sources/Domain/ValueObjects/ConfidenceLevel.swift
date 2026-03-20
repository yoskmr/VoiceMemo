import Foundation

/// 信頼度レベル（3段階）
/// 統合仕様書 INT-SPEC-001 準拠
/// TranscriptionResult の confidence 値に基づく3段階の信頼度表示
public enum ConfidenceLevel: String, Sendable, Equatable {
    /// confidence >= 0.7: 高信頼（そのまま使用可能）
    case high
    /// 0.4 <= confidence < 0.7: 中信頼（要確認表示）
    case medium
    /// confidence < 0.4: 低信頼（再録音推奨表示）
    case low

    /// confidence 値から信頼度レベルを判定する
    /// - Parameter confidence: 0.0 ~ 1.0 の信頼度値
    public init(confidence: Double) {
        switch confidence {
        case 0.7...:
            self = .high
        case 0.4..<0.7:
            self = .medium
        default:
            self = .low
        }
    }

    /// UIに表示するインジケーターカラー名
    public var indicatorColor: String {
        switch self {
        case .high:   return "green"
        case .medium: return "yellow"
        case .low:    return "red"
        }
    }
}
