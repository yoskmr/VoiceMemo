import Foundation

/// 録音保存処理に関するエラー
public enum SaveRecordingError: Error, Sendable, Equatable {
    /// ファイル移動に失敗（ストレージ不足等）
    case fileMoveFailed(String)
    /// ファイル保護レベルの設定に失敗
    case fileProtectionFailed(String)
    /// SwiftData保存に失敗
    case persistenceFailed(String)
    /// 一時ファイルのクリーンアップに失敗（非致命的）
    case cleanupFailed(String)
    /// STT確定に失敗（音声ファイルは保存される）
    case transcriptionFinalizeFailed(String)
}
