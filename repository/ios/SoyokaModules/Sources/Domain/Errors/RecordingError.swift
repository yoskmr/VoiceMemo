import Foundation

/// 録音処理に関するエラー
public enum RecordingError: Error, Sendable, Equatable {
    /// マイク使用権限が未許可
    case microphonePermissionDenied
    /// AVAudioSession の設定に失敗
    case audioSessionSetupFailed(String)
    /// 録音エンジンの起動に失敗
    case engineStartFailed(String)
    /// すでに録音中であるため開始できない
    case alreadyRecording
    /// 録音中ではないため操作できない
    case notRecording
    /// 一時停止中ではないため再開できない
    case notPaused
    /// 音声ファイルの保存に失敗
    case fileSaveFailed(String)
    /// チャンク結合に失敗
    case compositionFailed
    /// エクスポートに失敗
    case exportFailed
    /// ストレージ不足
    case insufficientStorage
    /// チャンクファイルが見つからない
    case noChunksFound
}
