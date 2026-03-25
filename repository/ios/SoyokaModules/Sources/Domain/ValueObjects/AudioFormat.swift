import Foundation

/// 音声ファイルフォーマット
public enum AudioFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case m4a
    case opus
}
