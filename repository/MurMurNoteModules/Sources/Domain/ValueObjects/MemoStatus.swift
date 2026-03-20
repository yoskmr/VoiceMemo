import Foundation

/// メモの処理ステータス
/// 統合仕様書準拠: recording, processing, completed, failed
public enum MemoStatus: String, Codable, Sendable, Equatable {
    case recording
    case processing
    case completed
    case failed
}
