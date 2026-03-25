import Foundation

/// 録音結果
/// 録音停止時に返却され、保存先URL・録音時間・フォーマットを含む
public struct RecordingResult: Sendable, Equatable {
    /// 保存された音声ファイルのURL
    public let fileURL: URL
    /// 録音時間（秒）
    public let duration: TimeInterval
    /// 音声フォーマット
    public let format: AudioFormat

    public init(fileURL: URL, duration: TimeInterval, format: AudioFormat) {
        self.fileURL = fileURL
        self.duration = duration
        self.format = format
    }
}
