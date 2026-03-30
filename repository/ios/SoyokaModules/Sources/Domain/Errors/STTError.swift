import Foundation

/// STTエンジンに関するエラー
/// 統合仕様書 INT-SPEC-001 準拠
public enum STTError: Error, Sendable, Equatable {
    /// エンジンが初期化されていない
    case engineNotInitialized
    /// 音声認識の権限が未許可
    case authorizationDenied
    /// 指定言語がサポートされていない
    case languageNotSupported(String)
    /// 音声認識エンジンが利用不可
    case engineUnavailable
    /// 認識中にエラーが発生
    case recognitionFailed(String)
    /// オンデバイス認識がサポートされていない
    case onDeviceRecognitionNotSupported
    /// 認識がキャンセルされた
    case cancelled
}
